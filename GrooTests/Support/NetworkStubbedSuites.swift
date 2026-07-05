//
//  NetworkStubbedSuites.swift
//  GrooTests
//
//  Shared serialization umbrella for suites that rely on StubURLProtocol's
//  static state. `@Suite(.serialized)` only serializes tests *within* a
//  suite; without a common parent, two independently-serialized suites can
//  still run concurrently with each other and race on the shared stub
//  queues/recorded requests. Nesting both suites under this one
//  `.serialized` parent makes Swift Testing serialize them relative to each
//  other as well.
//

import Testing

@Suite(.serialized)
struct NetworkStubbedSuites {}
