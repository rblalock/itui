import Foundation
import Testing

@testable import IMsgCore

private actor ContactFixture {
  var calls = 0
  var result: ContactResolver.LoadResult

  init(name: String) {
    result = Self.snapshot(name: name)
  }

  func load() -> ContactResolver.LoadResult {
    calls += 1
    return result
  }

  func change(name: String) { result = Self.snapshot(name: name) }

  func fail() {
    result = ContactResolver.LoadResult(
      authorization: .authorized, records: [], error: "Temporary error")
  }

  private static func snapshot(name: String) -> ContactResolver.LoadResult {
    ContactResolver.LoadResult(
      authorization: .authorized,
      records: [
        ContactResolver.ContactRecord(
          canonicalKey: "+15555550123", name: name, initials: "A", thumbnailData: nil,
          mime: nil, fileExtension: nil
        )
      ], error: nil
    )
  }
}

@Test
func contactResolverRefreshesNamesAndRevisions() async {
  let fixture = ContactFixture(name: "Before")
  let resolver = ContactResolver(avatarCacheDirectory: .temporaryDirectory) { await fixture.load() }
  #expect(await resolver.resolve("+15555550123").name == "Before")
  let before = await resolver.revision
  await fixture.change(name: "After")
  await resolver.invalidate()
  #expect(await resolver.resolve("+15555550123").name == "After")
  #expect(await resolver.revision != before)
  let after = await resolver.revision
  await resolver.refresh()
  #expect(await resolver.revision == after)
}

@Test
func contactResolverKeepsValidContactsDuringTransientFailuresAndRecovers() async {
  let fixture = ContactFixture(name: "Known")
  let resolver = ContactResolver(avatarCacheDirectory: .temporaryDirectory) { await fixture.load() }
  await resolver.loadIfNeeded()
  await fixture.fail()
  await resolver.refresh()
  #expect(await resolver.resolve("+15555550123").name == "Known")
  #expect(await resolver.lastError == "Temporary error")
  await fixture.change(name: "Recovered")
  await resolver.refresh()
  #expect(await resolver.resolve("+15555550123").name == "Recovered")
  #expect(await resolver.lastError == nil)
}

@Test
func contactResolverDoesNotPermanentlyCacheAnInitialFailedLoad() async {
  let fixture = ContactFixture(name: "Ready")
  await fixture.fail()
  let resolver = ContactResolver(avatarCacheDirectory: .temporaryDirectory) { await fixture.load() }
  #expect(await resolver.resolve("+15555550123").name == nil)
  await fixture.change(name: "Ready")
  await resolver.refresh()
  #expect(await resolver.resolve("+15555550123").name == "Ready")
}
