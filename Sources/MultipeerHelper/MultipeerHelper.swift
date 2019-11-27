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

  public let sessionType: SessionType
  public let serviceName: String
  public var syncService: MultipeerConnectivityService? {
    if syncServiceRK == nil {
      syncServiceRK = try? MultipeerConnectivityService(session: session)
    }
    return syncServiceRK
  }

  public let myPeerID = MCPeerID(displayName: UIDevice.current.name)
  private var session: MCSession!
  private var serviceAdvertiser: MCNearbyServiceAdvertiser?
  private var serviceBrowser: MCNearbyServiceBrowser?
  private var syncServiceRK: MultipeerConnectivityService?

  public weak var delegate: MultipeerHelperDelegate?

  /// - Parameters:
  ///   - serviceName: name of the service to be added, must be less than 15 lowercase ascii characters
  ///   - sessionType: Type of session (host, peer, both)
  ///   - delegate: optional `MultipeerHelperDelegate` for MultipeerConnectivity callbacks
  public init(
    serviceName: String,
    sessionType: SessionType = .both,
    delegate: MultipeerHelperDelegate? = nil
  ) {
    self.serviceName = serviceName
    self.sessionType = sessionType
    self.delegate = delegate

    super.init()
    session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
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

  public func sendToAllPeers(_ data: Data, reliably: Bool) {
    sendToPeers(data, reliably: reliably, peers: connectedPeers)
  }

  /// - Tag: SendToPeers
  func sendToPeers(_ data: Data, reliably: Bool, peers: [MCPeerID]) {
    guard !peers.isEmpty else { return }
    do {
      try session.send(data, toPeers: peers, with: reliably ? .reliable : .unreliable)
    } catch {
      print("error sending data to peers \(peers): \(error.localizedDescription)")
    }
  }

  public var connectedPeers: [MCPeerID] {
    session.connectedPeers
  }
}

extension MultipeerHelper: MCSessionDelegate {
  public func session(
    _: MCSession,
    peer peerID: MCPeerID,
    didChange state: MCSessionState
  ) {
    if state == .connected {
      delegate?.peerJoined(peerID)
    } else if state == .notConnected {
      delegate?.peerLeft(peerID)
    }
  }

  public func session(_: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
    delegate?.receivedData(data, peerID)
  }

  public func session(
    _: MCSession,
    didReceive stream: InputStream,
    withName streamName: String,
    fromPeer peerID: MCPeerID
  ) {
    delegate?.receivedStream(stream, streamName, peerID)
  }

  public func session(
    _: MCSession,
    didStartReceivingResourceWithName resourceName: String,
    fromPeer peerID: MCPeerID,
    with progress: Progress
  ) {
    delegate?.receivingResource(resourceName, peerID, progress)
  }

  public func session(
    _: MCSession,
    didFinishReceivingResourceWithName resourceName: String,
    fromPeer peerID: MCPeerID,
    at localURL: URL?,
    withError error: Error?
  ) {
    delegate?.receivedResource(resourceName, peerID, localURL, error)
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
    let accepted = delegate?.peerDiscovered(peerID)
    if accepted != false {
      browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }
  }

  public func browser(_: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
    delegate?.peerLost(peerID)
  }
}

extension MultipeerHelper: MCNearbyServiceAdvertiserDelegate {
  /// - Tag: AcceptInvite
  public func advertiser(
    _: MCNearbyServiceAdvertiser,
    didReceiveInvitationFromPeer _: MCPeerID,
    withContext _: Data?,
    invitationHandler: @escaping (Bool, MCSession?) -> Void
  ) {
    // Call the handler to accept the peer's invitation to join.
    invitationHandler(true, session)
  }
}
