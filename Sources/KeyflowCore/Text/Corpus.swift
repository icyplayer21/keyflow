import Foundation

/// Built-in practice passages. All original, all typable on a US keyboard.
public enum Corpus {
    /// Natural prose with capitals and light punctuation. Also used for tests.
    public static let sentences: [String] = lines("""
    The morning train was almost empty when she found a seat by the window.
    He kept a small notebook in his coat pocket and wrote in it every evening.
    Most of the garden had been planted before the first rain arrived.
    We walked along the river until the lights of the town came into view.
    The bakery on the corner sells out of fresh bread before nine each day.
    Nobody expected the meeting to finish early, but it was over within an hour.
    She learned to play the piano by listening to old records over and over.
    The children built a fort from blankets and refused to come out for dinner.
    A good map is worth more than a fast car when the roads are unfamiliar.
    They painted the kitchen yellow and it changed the mood of the whole house.
    The library stays open late during the winter, which suits the students well.
    I found the missing key under a pile of letters on the hallway table.
    Every summer the family drives north to spend two weeks beside the lake.
    The engineer checked each bolt twice before allowing the bridge to open.
    Our neighbor grows more tomatoes than any one household could ever eat.
    The old clock in the square has kept perfect time for over a century.
    After the storm passed, the air smelled clean and the streets were quiet.
    He answered the question slowly, choosing each word with unusual care.
    The team practiced the same simple routine until it became second nature.
    A long walk in the evening often solves problems that a desk cannot.
    She packed light, carrying only a camera, a jacket, and a worn paperback.
    The market fills with color on Saturdays when the flower sellers arrive.
    Learning a new skill takes patience, steady effort, and a little humor.
    The pilot announced a short delay and thanked everyone for their patience.
    We ordered soup because the weather had turned cold without any warning.
    The museum guide told stories that made the old paintings feel alive.
    His handwriting was so neat that people often mistook it for print.
    The dog waited by the door each afternoon until the school bus appeared.
    Small habits, repeated daily, tend to matter more than grand plans.
    The village sits high in the hills, far from the noise of the main road.
    She fixed the bicycle herself using tools borrowed from the shop next door.
    The recipe calls for butter, flour, two eggs, and a generous pinch of salt.
    They missed the last ferry and spent the night talking on the harbor wall.
    A quiet room and a clear schedule are all some people need to do good work.
    The teacher wrote the answer on the board and waited for someone to object.
    Fresh snow covered the path, so we followed the fence line back to the cabin.
    He saved a little money each month and bought the boat ten years later.
    The orchestra tuned for a moment, then the hall fell completely silent.
    Our flight landed early, which almost never happens on that route.
    The letter arrived three weeks late, but its news was still welcome.
    She read the instructions carefully before touching a single switch.
    The harvest was better than expected and the whole valley celebrated.
    Good writing is mostly rewriting, as every patient editor will tell you.
    The shop owner remembered my name even though I had visited only once.
    We climbed above the clouds and watched the sun rise over the far ridge.
    The repair took longer than planned because one small part was missing.
    He practiced typing for ten minutes a day and improved faster than he expected.
    The lake froze early that year, and skaters arrived before the end of the month.
    A careful plan saves time, yet no plan survives without some adjustment.
    The kitchen smelled of coffee and toast when the guests finally came downstairs.
    She smiled at the mistake, corrected it, and carried on without a pause.
    The bookshop keeps a cat that sleeps in the front window most afternoons.
    Traffic was light, so we reached the coast well before the tide turned.
    The candidate spoke plainly and the audience seemed to appreciate it.
    Their first attempt failed, but the second design worked on the very first try.
    The trail narrows near the summit, where the wind is strong and steady.
    I always forget how bright the stars look when you are far from the city.
    The doctor explained the results in simple terms and answered every question.
    He opened the window to let the cool evening air into the crowded room.
    The festival begins at dusk and ends long after the last lantern fades.
    She writes a short list every morning and rarely finishes all of it.
    The carpenter measured the board three times before making a single cut.
    We shared an umbrella and still arrived at the theater completely soaked.
    The river is wide here, slow and brown, and the far bank is thick with trees.
    Experience taught him to listen first and to speak only when it helped.
    The power went out at midnight, so we finished the game by candlelight.
    """)

    /// Passages dense with punctuation marks.
    public static let punctuation: [String] = lines("""
    "Wait," she said, "aren't you coming with us?"
    He paused; then, slowly, he opened the door.
    Bring three things: a pen, some paper, and patience.
    The answer (if there is one) isn't obvious.
    "Is it ready?" "Not yet - give me a minute!"
    Well, that's odd; it worked yesterday, didn't it?
    Her reply was short: "No, thanks."
    It's a long-term, low-risk plan; nothing more.
    Who's there? What's that noise? Where's the light?
    The cat's toys were everywhere: under chairs, behind doors, even in shoes.
    "Stop!" he shouted. "You've dropped your keys!"
    We can't, won't, and shouldn't ignore it.
    Yes, no, maybe - honestly, I don't know.
    The so-called "expert" didn't have an answer, either.
    Note: doors open at 7; the show starts at 8 (sharp).
    "Why now?" I asked; she shrugged and said, "Why not?"
    After all, it's theirs - not ours, not yours, not mine.
    He wrote, "See you soon!", then crossed it out.
    First, breathe; second, think; third, act.
    They're late (again), and it's raining (of course).
    "Don't," she warned, "touch that switch - it's live!"
    Is this yours, or hers, or somebody else's?
    The well-known, much-loved author signed every copy; I've kept mine.
    Slow down: commas, colons, and semicolons aren't a race.
    "If it's free," he said, "what's the catch?"
    Really? You're sure? Absolutely, completely sure?
    It wasn't luck; it was practice, patience, and timing.
    The sign read: "Closed - back in ten minutes."
    We'd planned for rain; we hadn't planned for snow!
    One question remains: who's paying, and when?
    "Oh," said the clerk, "that's last year's form; here's the new one."
    Sorry, I can't; I've got a two-hour, one-on-one meeting.
    She's quick, he's careful; together, they're unbeatable.
    Wait - did you say "left" or "right"?
    The list was simple: eggs, milk, bread; nothing else.
    "Well done!" they cried. "That's a first, isn't it?"
    It's not what you said; it's how (and when) you said it.
    Hmm, let's see: north, then east, then - no, west!
    Everyone's ready, aren't they? Then let's begin.
    The so-so review didn't matter; the play's run was sold out.
    """)

    private static func lines(_ block: String) -> [String] {
        block.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
