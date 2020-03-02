//
//  MultipeerHelper.swift
//
//
//  Created by Max Cobb on 11/22/19.
//

import MultipeerConnectivity
import RealityKit

public class MultipeerHelper: NSObject {
  /// What type of session you want to make.
  ///
  /// `both` creates a session where all users are equal
  /// Otherwise if you want one specific user to be the host, choose `host` and `peer`
  public enum SessionType: Int {
    case host = 1
    case peer = 2
    case both = 3
  }

  /// Detemines whether your service is advertising, browsing, or both.
  public let sessionType: SessionType
  public let serviceName: String

  /// Used for RealityKit, set this as your scene's synchronizationService
  public var syncService: MultipeerConnectivityService? {
    if syncServiceRK == nil {
      syncServiceRK = try? MultipeerConnectivityService(session: session)
    }
    return syncServiceRK
  }

  public let myPeerID = MCPeerID(displayName: UIDevice.current.name)

  /// Quick lookup for a peer given their displayName
  private var peerIDLookup: [String: MCPeerID] = [:]

  /// The MultipeerConnectivity session being used
  public private(set) var session: MCSession!
  public private(set) var serviceAdvertiser: MCNearbyServiceAdvertiser?
  public private(set) var serviceBrowser: MCNearbyServiceBrowser?
  private var syncServiceRK: MultipeerConnectivityService?

  public weak var delegate: MultipeerHelperDelegate?

  /// - Parameters:
  ///   - serviceName: name of the service to be added, must be less than 15 lowercase ascii characters
  ///   - sessionType: Type of session (host, peer, both)
  ///   - encryptionPreference: optional `MCEncryptionPreference`, defaults to `.required`
  ///   - delegate: optional `MultipeerHelperDelegate` for MultipeerConnectivity callbacks
  public init(
    serviceName: String,
    sessionType: SessionType = .both,
    encryptionPreference: MCEncryptionPreference = .required,
    delegate: MultipeerHelperDelegate? = nil
  ) {
    self.serviceName = serviceName
    self.sessionType = sessionType
    self.delegate = delegate

    super.init()
    peerIDLookup[myPeerID.displayName] = myPeerID
    session = MCSession(
      peer: myPeerID,
      securityIdentity: nil,
      encryptionPreference: encryptionPreference
    )
    session.delegate = self

    if (self.sessionType.rawValue & SessionType.host.rawValue) != 0 {
      serviceAdvertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: self.serviceName)
      serviceAdvertiser?.delegate = self
      serviceAdvertiser?.startAdvertisingPeer()
    }

    if (self.sessionType.rawValue & SessionType.peer.rawValue) != 0 {
      serviceBrowser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: self.serviceName)
      serviceBrowser?.delegate = self
      serviceBrowser?.startBrowsingForPeers()
    }
  }

  /// Data to be sent to all of the connected peers
  /// - Parameters:
  ///   - data: Encoded data to be sent
  ///   - reliably: The transmission mode to use (true for data to be sent reliably).
  @discardableResult
  public func sendToAllPeers(_ data: Data, reliably: Bool = true) -> Bool {
    return sendToPeers(data, reliably: reliably, peers: connectedPeers)
  }

  /// Data to be sent to a list of peers
  /// - Parameters:
  ///   - data: encoded data to be sent
  ///   - reliably: The transmission mode to use (true for data to be sent reliably).
  ///   - peers: An array of all the peers to rec3ive your data
  @discardableResult
  public func sendToPeers(_ data: Data, reliably: Bool, peers: [MCPeerID]) -> Bool {
    guard !peers.isEmpty else { return false }
    do {
      try session.send(data, toPeers: peers, with: reliably ? .reliable : .unreliable)
    } catch {
      print("error sending data to peers \(peers): \(error.localizedDescription)")
      return false
    }
    return true
  }

  public var connectedPeers: [MCPeerID] {
    session.connectedPeers
  }

  /// Data to be send to peer using their displayname
  /// - Parameters:
  ///   - displayname: displayname of the peer you want to be sent
  ///   - data: encoded data to be sent
  ///   - reliably: The transmission mode to use (true for data to be sent reliably).
  public func sendToPeer(named displayname: String, data: Data, reliably: Bool = true) -> Bool {
    guard let recipient = self.findPeer(name: displayname) else {
      return false
    }
    return self.sendToPeers(data, reliably: reliably, peers: [recipient])
  }

  /// Look up a peer given their displayname
  /// - Parameter name: The displayname of the peer you are looking for
  public func findPeer(name: String) -> MCPeerID? {
    if let peer = self.peerIDLookup[name] {
      return peer
    }
    defer {
      // In case for some reason the peerIDLookup is out of sync, recalculate it
      self.peerIDLookup.removeAll(keepingCapacity: false)
      for connectedPeer in self.connectedPeers {
        self.peerIDLookup[connectedPeer.displayName] = connectedPeer
      }
    }
    return connectedPeers.first { $0.displayName == name }
  }
}

extension MultipeerHelper: MCSessionDelegate {

  public func session(_ session: MCSession, didReceiveCertificate certificate: [Any]?, fromPeer peerID: MCPeerID, certificateHandler: @escaping (Bool) -> Void) {
    certificateHandler(true)
  }

  public func session(
    _: MCSession,
    peer peerID: MCPeerID,
    didChange state: MCSessionState
  ) {
    if state == .connected {
      peerIDLookup[peerID.displayName] = peerID
      delegate?.peerJoined?(peerID)
    } else if state == .notConnected {
      peerIDLookup.removeValue(forKey: peerID.displayName)
      delegate?.peerLeft?(peerID)
    }
  }

  public func session(_: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
    delegate?.receivedData?(data, peerID)
  }

  public func session(
    _: MCSession,
    didReceive stream: InputStream,
    withName streamName: String,
    fromPeer peerID: MCPeerID
  ) {
    delegate?.receivedStream?(stream, streamName, peerID)
  }

  public func session(
    _: MCSession,
    didStartReceivingResourceWithName resourceName: String,
    fromPeer peerID: MCPeerID,
    with progress: Progress
  ) {
    delegate?.receivingResource?(resourceName, peerID, progress)
  }

  public func session(
    _: MCSession,
    didFinishReceivingResourceWithName resourceName: String,
    fromPeer peerID: MCPeerID,
    at localURL: URL?,
    withError error: Error?
  ) {
    delegate?.receivedResource?(resourceName, peerID, localURL, error)
  }
}

extension MultipeerHelper: MCNearbyServiceBrowserDelegate {
  /// - Tag: SendPeerInvite
  public func browser(
    _ browser: MCNearbyServiceBrowser,
    foundPeer peerID: MCPeerID,
    withDiscoveryInfo _: [String: String]?
  ) {
    // Ask the handler whether we should invite this peer or not
    if delegate?.shouldSendJoinRequest == nil || (delegate?.shouldSendJoinRequest?(peerID) ?? false) {
      print("BrowserDelegate \(peerID)")
      browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }
  }

  public func browser(_: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
    delegate?.peerLost?(peerID)
  }
}

extension MultipeerHelper: MCNearbyServiceAdvertiserDelegate {
  /// - Tag: AcceptInvite
  public func advertiser(
    _: MCNearbyServiceAdvertiser,
    didReceiveInvitationFromPeer peerID: MCPeerID,
    withContext data: Data?,
    invitationHandler: @escaping (Bool, MCSession?) -> Void
  ) {
    // Call the handler to accept the peer's invitation to join.
    let shouldAccept = self.delegate?.shouldAcceptJoinRequest?(peerID: peerID, context: data)
    invitationHandler(shouldAccept != nil ? shouldAccept! : true, self.session)
  }
}
