const orb = @import("orb");

const Node = orb.dialogue.Node;
const NONE = orb.dialogue.NONE;

/// Dialogue script for Arawn.
pub const NODES: []const Node = &.{
    .{ .text = "I am Arawn, King of Annwn.", .next = 1 },
    .{ .text = "Will you exchange forms with me for a year and a day?", .choice = .{
        .labels = .{ "I will", "I refuse" },
        .next = .{ 2, 3 },
    } },
    .{ .text = "A shame. The forest remembers all who pass through." },
    .{ .text = "Not all who dream are asleep." },
    .{ .text = "Then it is agreed. We shall meet again at the appointed time." },
    .{ .text = "An ancient stone carved with spirals and strange marks.", .next = 6 },
    .{ .text = "It speaks of a king who rules the world below.", .sets_flag = 0 },
    .{ .text = "You have read the stone. Then you know what I am.", .next = 8 },
    .{ .text = "I am Arawn, and I have need of you.", .next = 1 },
};
