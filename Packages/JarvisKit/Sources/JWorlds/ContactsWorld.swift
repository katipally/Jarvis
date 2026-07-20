import Contacts
import Foundation
import JKnowledge

/// Contacts → deterministic graph (no LLM): people with nickname/email aliases,
/// `works_at` from the organization field, family relations from labeled
/// values. The Me card becomes aliases of the is_self node.
public struct ContactsWorld: WorldConnector {
    public let worldId = "contacts"

    public init() {}

    struct Cursor: Codable {
        var fingerprints: [String: String] = [:]
    }

    static var keys: [CNKeyDescriptor] {
        [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey,
         CNContactOrganizationNameKey, CNContactEmailAddressesKey, CNContactRelationsKey] as [NSString]
    }

    public func sync(cursorJson: String?) async throws -> WorldSyncResult {
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
            throw WorldError.accessDenied("Contacts")
        }
        let store = CNContactStore()
        let request = CNContactFetchRequest(keysToFetch: Self.keys)
        var contacts: [CNContact] = []
        try store.enumerateContacts(with: request) { contact, _ in contacts.append(contact) }

        let old = WorldCursor.decode(cursorJson, as: Cursor.self) ?? Cursor()
        var fresh: [String: String] = [:]
        var byID: [String: CNContact] = [:]
        for contact in contacts {
            let name = Self.displayName(contact)
            guard !name.isEmpty else { continue }
            let emails = contact.emailAddresses.map { $0.value as String }.sorted().joined(separator: ",")
            let relations = contact.contactRelations.map { "\($0.label ?? ""):\($0.value.name)" }.sorted().joined(separator: ",")
            fresh[contact.identifier] = SnapshotDiff.hash([name, contact.nickname,
                                                           contact.organizationName, emails, relations])
            byID[contact.identifier] = contact
        }

        let (added, changed, _) = SnapshotDiff.diff(old: old.fingerprints, new: fresh)
        var result = WorldSyncResult(cursorJson: WorldCursor.encode(Cursor(fingerprints: fresh)))

        // Me card → aliases of the is_self node, never a separate person.
        let meName: String?
        if let me = try? store.unifiedMeContactWithKeys(toFetch: Self.keys) {
            let name = Self.displayName(me)
            meName = name.isEmpty ? nil : name
            if let meName {
                result.ops.entities.append(EntityOp(name: meName, type: .person,
                                                    aliases: me.emailAddresses.map { $0.value as String },
                                                    selfAlias: true))
            }
        } else {
            meName = nil
        }

        for id in added + changed {
            guard let contact = byID[id] else { continue }
            let name = Self.displayName(contact)
            if name == meName { continue }

            var aliases = contact.emailAddresses.map { $0.value as String }
            if !contact.nickname.isEmpty { aliases.append(contact.nickname) }
            result.ops.entities.append(EntityOp(name: name, type: .person, aliases: aliases))

            let org = contact.organizationName.trimmingCharacters(in: .whitespaces)
            if !org.isEmpty {
                result.ops.edges.append(EdgeOp(subject: name, subjectType: .person, rel: "works_at",
                                               object: org, objectType: .org))
            }
            for relation in contact.contactRelations {
                guard let rel = Self.familyRel(relation.label), !relation.value.name.isEmpty else { continue }
                result.ops.edges.append(EdgeOp(subject: name, subjectType: .person, rel: rel,
                                               object: relation.value.name, objectType: .person))
            }
        }
        return result
    }

    static func displayName(_ contact: CNContact) -> String {
        [contact.givenName, contact.familyName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    static func familyRel(_ label: String?) -> String? {
        switch label {
        case CNLabelContactRelationSpouse, CNLabelContactRelationPartner: "married_to"
        case CNLabelContactRelationChild, CNLabelContactRelationSon, CNLabelContactRelationDaughter: "parent_of"
        case CNLabelContactRelationParent, CNLabelContactRelationMother, CNLabelContactRelationFather: "child_of"
        case CNLabelContactRelationBrother, CNLabelContactRelationSister, CNLabelContactRelationSibling: "sibling_of"
        case CNLabelContactRelationFriend: "knows"
        default: nil
        }
    }
}
