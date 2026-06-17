//
//  ParticipantVideoRegistry.swift
//
//  RETIRED. The per-tile renderer registry and the shared single-feed registry were
//  replaced by a single cached renderer owner, `RemoteVideoRenderManager`, which keys
//  one `VideoStreamRenderer` per `participantId:streamId` and serves both the
//  single-remote full-screen view and the grid tiles. Tile containers are now owned by
//  `ParticipantTileContainerRegistry` (in `AcsVideoViewFactory.swift`).
//
//  This file is intentionally left without code. It is kept (rather than removed) so the
//  existing generated Pods project — which references this path in its compile sources —
//  still builds without a fresh `pod install`. It may be deleted at the next install.
//
