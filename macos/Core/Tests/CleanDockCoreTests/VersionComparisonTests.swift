//
//  VersionComparisonTests.swift
//  CleanDock
//
//  Created by p1w0 on 19.08.26.
//

import Testing
@testable import CleanDockCore

@Suite("Version comparison")
struct VersionComparisonTests {
    @Test("Newer versions are detected component-wise")
    func newerVersions() {
        #expect(CleanDockInfo.isVersion("1.0.1", newerThan: "1.0.0"))
        #expect(CleanDockInfo.isVersion("1.1.0", newerThan: "1.0.9"))
        #expect(CleanDockInfo.isVersion("2.0.0", newerThan: "1.9.9"))
        #expect(CleanDockInfo.isVersion("1.0.10", newerThan: "1.0.9"))
    }

    @Test("Equal and older versions are not newer")
    func equalAndOlder() {
        #expect(!CleanDockInfo.isVersion("1.0.0", newerThan: "1.0.0"))
        #expect(!CleanDockInfo.isVersion("1.0.0", newerThan: "1.0.1"))
        #expect(!CleanDockInfo.isVersion("0.9.9", newerThan: "1.0.0"))
    }

    @Test("Missing components count as zero")
    func missingComponents() {
        #expect(CleanDockInfo.isVersion("1.0.1", newerThan: "1.0"))
        #expect(!CleanDockInfo.isVersion("1.0", newerThan: "1.0.0"))
        #expect(CleanDockInfo.isVersion("1.1", newerThan: "1.0.5"))
    }
}
