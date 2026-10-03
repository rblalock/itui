import Contacts
import Foundation

extension ContactResolver {
  static func fetchAllContacts() async -> LoadResult {
    let store = CNContactStore()
    var status = CNContactStore.authorizationStatus(for: .contacts)

    if status == .notDetermined {
      _ = await withCheckedContinuation { continuation in
        store.requestAccess(for: .contacts) { granted, _ in
          continuation.resume(returning: granted)
        }
      }
      status = CNContactStore.authorizationStatus(for: .contacts)
    }

    let mappedStatus: ContactAuthorizationStatus
    switch status {
    case .notDetermined: mappedStatus = .notDetermined
    case .restricted: mappedStatus = .restricted
    case .denied: mappedStatus = .denied
    case .authorized: mappedStatus = .authorized
    @unknown default: mappedStatus = .notDetermined
    }

    let keysToFetch: [CNKeyDescriptor] = [
      CNContactGivenNameKey as CNKeyDescriptor,
      CNContactFamilyNameKey as CNKeyDescriptor,
      CNContactOrganizationNameKey as CNKeyDescriptor,
      CNContactPhoneNumbersKey as CNKeyDescriptor,
      CNContactEmailAddressesKey as CNKeyDescriptor,
      CNContactThumbnailImageDataKey as CNKeyDescriptor,
      CNContactImageDataAvailableKey as CNKeyDescriptor,
    ]

    let request = CNContactFetchRequest(keysToFetch: keysToFetch)

    var records: [ContactRecord] = []

    do {
      try store.enumerateContacts(with: request) { contact, _ in
        let name = [contact.givenName, contact.familyName]
          .filter { !$0.isEmpty }
          .joined(separator: " ")
        let displayName: String
        if !name.isEmpty {
          displayName = name
        } else if !contact.organizationName.isEmpty {
          displayName = contact.organizationName
        } else {
          displayName = ""
        }
        let initials = ContactResolver.computeInitials(
          given: contact.givenName,
          family: contact.familyName,
          organization: contact.organizationName
        )
        let thumb = contact.thumbnailImageData
        let mimeInfo = thumb.flatMap { ContactResolver.detectMime(from: $0) }

        // Each contact record is emitted once per phone number and once per email address
        // so that a handle from the Messages DB resolves deterministically to the same
        // record regardless of which endpoint was used.
        let phoneValues = contact.phoneNumbers.map { $0.value.stringValue }
        let emailValues = contact.emailAddresses.map { $0.value as String }

        if !phoneValues.isEmpty {
          for raw in phoneValues {
            let canonical = raw
            records.append(
              ContactRecord(
                canonicalKey: canonical,
                name: displayName,
                initials: initials,
                thumbnailData: thumb,
                mime: mimeInfo?.mime,
                fileExtension: mimeInfo?.ext
              )
            )
          }
        }

        for email in emailValues {
          let canonical = email.lowercased()
          records.append(
            ContactRecord(
              canonicalKey: canonical,
              name: displayName,
              initials: initials,
              thumbnailData: thumb,
              mime: mimeInfo?.mime,
              fileExtension: mimeInfo?.ext
            )
          )
        }
      }
    } catch {
      // Permission denied or enumeration failed — caller sees empty records + reported status.
      return LoadResult(authorization: mappedStatus, records: [], error: String(describing: error))
    }

    return LoadResult(authorization: mappedStatus, records: records, error: nil)
  }
}

/// NotificationCenter owns an immutable token; all cache mutations stay on the actor.
final class ContactChangeObservation: @unchecked Sendable {
  private let token: any NSObjectProtocol

  init(onChange: @escaping @Sendable () -> Void) {
    token = NotificationCenter.default.addObserver(
      forName: .CNContactStoreDidChange, object: nil, queue: nil
    ) { _ in onChange() }
  }

  deinit { NotificationCenter.default.removeObserver(token) }
}
