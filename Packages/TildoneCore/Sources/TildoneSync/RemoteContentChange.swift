//
//  RemoteContentChange.swift
//  Tildone
//

import TildoneDomain

public struct RemoteContentChange: Hashable, Sendable {
    public let changedRecords: Set<DomainRecordID>

    public init(changedRecords: Set<DomainRecordID>) {
        self.changedRecords = changedRecords
    }
}
