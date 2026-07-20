import Testing
@testable import JMemory

@Suite struct MemoryValidatorTests {
    // The exact junk the on-device model saved in production.
    @Test func rejectsProductionJunk() {
        #expect(!MemoryValidator.isDurable("Can you hear me?"))
        #expect(!MemoryValidator.isDurable("Hello?"))
        #expect(!MemoryValidator.isDurable("User is engaging with Jarvis, a Mac notch-side assistant."))
        #expect(!MemoryValidator.isDurable("User has 22 unstaged changes in their git working directory."))
    }

    @Test func rejectsQuestionsAndFragments() {
        #expect(!MemoryValidator.isDurable("What time is it in Tokyo?"))
        #expect(!MemoryValidator.isDurable("Loves sushi"))
        #expect(!MemoryValidator.isDurable("ok"))
        #expect(!MemoryValidator.isDurable(""))
    }

    @Test func rejectsGreetingsAndTests() {
        #expect(!MemoryValidator.isDurable("Hello there, how are you today"))
        #expect(!MemoryValidator.isDurable("Testing whether the microphone is working"))
        #expect(!MemoryValidator.isDurable("Thanks for all the help with that"))
    }

    @Test func rejectsMetaAndTransient() {
        #expect(!MemoryValidator.isDurable("User is chatting with the assistant about code."))
        #expect(!MemoryValidator.isDurable("User's frontmost app is Xcode at the moment."))
        #expect(!MemoryValidator.isDurable("The clipboard contains a URL the user copied."))
    }

    @Test func rejectsVerbatimEchoes() {
        let source = "I really need to finish the deck tonight"
        #expect(!MemoryValidator.isDurable("I really need to finish the deck tonight", source: source))
        // A distilled third-person rewrite of the same source passes.
        #expect(MemoryValidator.isDurable("User is preparing a presentation deck.", source: source))
    }

    @Test func acceptsDurableFacts() {
        #expect(MemoryValidator.isDurable("User prefers dark roast coffee."))
        #expect(MemoryValidator.isDurable("User is building Jarvis, a macOS notch app."))
        #expect(MemoryValidator.isDurable("User's garage code is 1234."))
        #expect(MemoryValidator.isDurable("User works at Anthropic on the API team."))
        #expect(MemoryValidator.isDurable("No sugar in coffee for the user."))
    }

    @Test func entityRolesAreNotEntities() {
        #expect(!MemoryValidator.isRealEntity("User"))
        #expect(!MemoryValidator.isRealEntity("the user"))
        #expect(!MemoryValidator.isRealEntity("Assistant"))
        #expect(MemoryValidator.isRealEntity("Jarvis"))
        #expect(MemoryValidator.isRealEntity("Anthropic"))
    }
}
