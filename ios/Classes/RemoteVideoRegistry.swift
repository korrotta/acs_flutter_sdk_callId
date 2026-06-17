//
//  RemoteVideoRegistry.swift
//
//  RETIRED. The shared single-feed renderer registry was replaced by the single cached
//  renderer owner, `RemoteVideoRenderManager`, which keys one `VideoStreamRenderer` per
//  `participantId:streamId` and serves both the single-remote full-screen view and the
//  grid tiles.
//
//  This file is intentionally left without code. It is kept (rather than removed) so the
//  existing generated Pods project — which references this path in its compile sources —
//  still builds without a fresh `pod install`. It may be deleted at the next install.
//
