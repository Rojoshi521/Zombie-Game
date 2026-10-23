-- Content tables. Names, backgrounds and traits come from the design bible.
local D = {}

D.APTITUDES = {
  "Combat", "Engineering", "Scouting", "Scavenging", "Medicine",
  "Research", "Agriculture", "Fabrication", "Logistics", "Leadership",
}

-- The groups that exist in this prototype. The other eight come later.
D.GROUPS = { "Combat", "Agriculture" }

D.GROUP_COLORS = {
  Combat = { 0.70, 0.24, 0.19 },
  Agriculture = { 0.43, 0.60, 0.27 },
}

D.GROUP_WORKPLACE = {
  Combat = "Box Truck Armory (drilling)",
  Agriculture = "Salvage Garden (farming)",
}

D.COMBAT_ATTRS = { "Accuracy", "Endurance", "Mobility", "Composure", "Awareness", "Handling" }

D.FIRST_NAMES = {
  "Ada", "Abel", "Bea", "Bo", "Cass", "Cyrus", "Dee", "Dmitri", "Eli", "Esme",
  "Faye", "Gus", "Hana", "Hollis", "Ines", "Jo", "Jonah", "Kai", "Lena", "Lou",
  "Mara", "Milo", "Nadia", "Nico", "Odette", "Otis", "Pia", "Quinn", "Rosa", "Rhys",
  "Sam", "Sol", "Tess", "Theo", "Uma", "Vic", "Wren", "Xavi", "Yara", "Zeke",
}

D.LAST_NAMES = {
  "Abara", "Brandt", "Castillo", "Doyle", "Eklund", "Fischer", "Garza", "Haddad",
  "Ishikawa", "Jovanovic", "Kowalski", "Lindqvist", "Mbeki", "Novak", "Okafor",
  "Petrov", "Quill", "Ramos", "Sato", "Thorne", "Underwood", "Vance", "Whitlock",
  "Xu", "Yilmaz", "Zielinski", "Boone", "Carver", "Dunmore", "Hale",
}

D.SKIN_TONES = {
  { 0.96, 0.80, 0.66 }, { 0.87, 0.67, 0.50 }, { 0.73, 0.52, 0.36 },
  { 0.55, 0.37, 0.24 }, { 0.38, 0.25, 0.16 },
}

-- { background, primary lean, secondary lean }
D.BACKGROUNDS = {
  { "Infantry Veteran", "Combat", "Leadership" },
  { "Firefighter", "Medicine", "Engineering" },
  { "Paramedic", "Medicine", "Combat" },
  { "Police Dispatcher", "Leadership", "Scouting" },
  { "Security Guard", "Combat", "Scouting" },
  { "Search-and-Rescue Volunteer", "Scouting", "Medicine" },
  { "Fire Inspector", "Engineering", "Scouting" },
  { "Correctional Officer", "Combat", "Leadership" },
  { "Auto Mechanic", "Engineering", "Fabrication" },
  { "Electrician", "Engineering", "Research" },
  { "Plumber", "Engineering", "Agriculture" },
  { "Welder", "Fabrication", "Engineering" },
  { "Construction Foreman", "Engineering", "Leadership" },
  { "Elevator Technician", "Engineering", "Logistics" },
  { "Machinist", "Fabrication", "Research" },
  { "Roofer", "Engineering", "Scouting" },
  { "IT Support Technician", "Research", "Logistics" },
  { "Amateur Radio Operator", "Scouting", "Research" },
  { "Laboratory Technician", "Research", "Medicine" },
  { "Robotics Hobbyist", "Research", "Fabrication" },
  { "Cartographer", "Scouting", "Research" },
  { "Meteorologist", "Scouting", "Research" },
  { "Chemistry Student", "Research", "Fabrication" },
  { "Arcade Repair Technician", "Research", "Engineering" },
  { "Registered Nurse", "Medicine", "Leadership" },
  { "Pharmacist", "Medicine", "Research" },
  { "Veterinary Technician", "Medicine", "Agriculture" },
  { "Dental Hygienist", "Medicine", "Logistics" },
  { "Physical Therapist", "Medicine", "Combat" },
  { "Elder Care Worker", "Medicine", "Leadership" },
  { "Hospital Custodian", "Medicine", "Engineering" },
  { "Mental Health Counselor", "Leadership", "Medicine" },
  { "Farmhand", "Agriculture", "Engineering" },
  { "Beekeeper", "Agriculture", "Research" },
  { "Groundskeeper", "Agriculture", "Engineering" },
  { "Recreational Hunter", "Scouting", "Combat" },
  { "Park Ranger", "Scouting", "Leadership" },
  { "Commercial Fisher", "Agriculture", "Scouting" },
  { "Pest Control Technician", "Scavenging", "Research" },
  { "Greenhouse Grower", "Agriculture", "Research" },
  { "Long-Haul Truck Driver", "Logistics", "Scouting" },
  { "Bicycle Courier", "Logistics", "Scouting" },
  { "Train Conductor", "Logistics", "Leadership" },
  { "Forklift Operator", "Logistics", "Engineering" },
  { "Delivery Dispatcher", "Logistics", "Leadership" },
  { "Vehicle Recovery Operator", "Scavenging", "Engineering" },
  { "Airport Baggage Handler", "Logistics", "Scavenging" },
  { "Airport Ground Crew Worker", "Engineering", "Logistics" },
  { "Restaurant Cook", "Agriculture", "Fabrication" },
  { "Casino Pit Boss", "Leadership", "Scouting" },
  { "Pawnshop Clerk", "Scavenging", "Logistics" },
  { "Shopping Mall Manager", "Logistics", "Leadership" },
  { "Gas Station Attendant", "Logistics", "Scavenging" },
  { "Retail Cashier", "Logistics", "Leadership" },
  { "Restaurant Server", "Leadership", "Logistics" },
  { "Hotel Housekeeper", "Medicine", "Logistics" },
  { "Elementary School Teacher", "Leadership", "Research" },
  { "Librarian", "Research", "Logistics" },
  { "City Archivist", "Research", "Leadership" },
  { "Youth Sports Coach", "Leadership", "Combat" },
  { "School Custodian", "Engineering", "Logistics" },
  { "Newspaper Photographer", "Scouting", "Research" },
  { "Community Organizer", "Leadership", "Scavenging" },
  { "Museum Conservator", "Research", "Fabrication" },
  { "Carnival Ride Operator", "Engineering", "Scouting" },
  { "Waterpark Lifeguard", "Scouting", "Medicine" },
  { "Bowling Alley Mechanic", "Engineering", "Fabrication" },
  { "Soda Bottling Line Worker", "Fabrication", "Logistics" },
  { "Ice Cream Truck Vendor", "Logistics", "Leadership" },
  { "Funeral Home Attendant", "Medicine", "Leadership" },
  { "Movie Prop Maker", "Fabrication", "Research" },
  { "Urban Guerrilla Gardener", "Agriculture", "Scavenging" },
}

-- Only traits whose effect is simulated in this prototype are listed.
-- Multiplied mods: learn, work, farm, cd, speed, arm, dmgTaken.
-- Added mods: acc, range, hp, react, startle, waste.
D.TRAITS = {
  { name = "Quick Learner", good = true, text = "Learns proficiency more quickly", mods = { learn = 1.5 } },
  { name = "Efficient", good = true, text = "Faster repetitive production tasks", mods = { work = 1.2 } },
  { name = "Patient Grower", good = true, text = "Better at delicate crop tasks", mods = { farm = 1.3 } },
  { name = "Steady Nerves", good = true, text = "Less panic under intense combat", mods = { acc = 0.08 } },
  { name = "Eagle-Eyed", good = true, text = "Improved awareness at range", mods = { range = 1 } },
  { name = "Quick Reflexes", good = true, text = "Faster reactions to sudden threats", mods = { cd = 0.85 } },
  { name = "Light-Footed", good = true, text = "More effective movement in rough terrain", mods = { speed = 1.12 } },
  { name = "Tough as Nails", good = true, text = "Less physical exhaustion", mods = { hp = 20 } },
  { name = "Rapid Responder", good = true, text = "Faster emergency mobilization", mods = { arm = 0.4 } },
  { name = "Cover-Savvy", good = true, text = "More effective use of cover", mods = { dmgTaken = 0.85 } },
  { name = "Clumsy", good = false, text = "More mistakes with unfamiliar equipment", mods = { acc = -0.08 } },
  { name = "Procrastinator", good = false, text = "Slower starts on nonurgent work", mods = { work = 0.85 } },
  { name = "Stubborn", good = false, text = "Slower to learn new procedures", mods = { learn = 0.7 } },
  { name = "Easily Startled", good = false, text = "Poor response to surprise attacks", mods = { startle = 0.12 } },
  { name = "Slow to React", good = false, text = "Slower response to rapid changes", mods = { cd = 1.2 } },
  { name = "Heavy Sleeper", good = false, text = "Slow emergency wake-up response", mods = { react = 4 } },
  { name = "Wasteful", good = false, text = "Consumes more production materials", mods = { waste = 0.35 } },
  { name = "Reckless", good = false, text = "Less effective use of cover", mods = { dmgTaken = 1.15 } },
}

D.WEAPONS = {
  rifle = { name = "Rifle", range = 7, dmg = 20, cd = 1.0, ranged = true },
  pistol = { name = "Pistol", range = 4.5, dmg = 12, cd = 0.55, ranged = true },
  improvised = { name = "Improvised", range = 0.95, dmg = 15, cd = 0.9 },
  fists = { name = "Bare hands", range = 0.85, dmg = 5, cd = 1.0 },
}

-- What a ranged weapon becomes when the settlement runs out of ammunition.
D.BASH = { name = "Empty (bashing)", range = 0.95, dmg = 6, cd = 1.0 }

D.LOADOUTS = { "rifle", "pistol", "improvised" }
D.LOADOUT_LABELS = { rifle = "Rifles", pistol = "Pistols", improvised = "Improvised" }

-- Only headquarters whose passive is simulated are offered. The Abandoned
-- Cathedral (happiness) and Dilapidated Campus (research) already have art in
-- assets/buildings and join once those systems exist.
D.HQS = {
  {
    id = "farmhouse", name = "Old Farmhouse with Barn", passive = "Agriculture",
    text = "Improved agricultural production: every farmer grows 30% more food.",
  },
  {
    id = "watertower", name = "Drained Water Tower", passive = "Scouting",
    text = "Better scouting awareness: twice the warning time before each wave.",
  },
  {
    id = "ferriswheel", name = "Defunct Ferris Wheel", passive = "Scavenging",
    text = "Increased salvage: 50% more scrap recovered after every wave.",
  },
  {
    id = "casino", name = "Half-Working Casino", passive = "Luck",
    text = "A 35% chance of an extra supply cache after each successful wave.",
  },
  {
    id = "broadcast", name = "Worn-Down Broadcast Station", passive = "Leadership",
    text = "Better coordinated training: survivors learn skills 40% faster.",
  },
  {
    id = "hospital", name = "Charred Hospital", passive = "Medicine",
    text = "Quicker recovery: survivors heal 3x faster, and the downed last twice as long.",
  },
}

-- Painted building sprites (made by tools/process_art.lua). ax, ay is the
-- pixel that sits on the centre of the footprint; scale converts the art to
-- world size.
D.SPRITES = {
  farmhouse = { ax = 398, ay = 268, scale = 0.48 },
  watertower = { ax = 392, ay = 336, scale = 0.48 },
  ferriswheel = { ax = 393, ay = 346, scale = 0.48 },
  casino = { ax = 393, ay = 322, scale = 0.48 },
  broadcast = { ax = 390, ay = 348, scale = 0.48 },
  cathedral = { ax = 390, ay = 333, scale = 0.48 },
  campus = { ax = 398, ay = 322, scale = 0.48 },
  coop = { ax = 398, ay = 280, scale = 0.48 },
}

D.ZOMBIES = {
  walker = { name = "Walker", hp = 45, speed = 0.8, dmg = 8, cd = 1.2, structDmg = 10, radius = 0.26, aggro = 4.5 },
  runner = { name = "Runner", hp = 28, speed = 1.75, dmg = 6, cd = 0.8, structDmg = 5, radius = 0.24, aggro = 6.5 },
  brute = { name = "Brute", hp = 240, speed = 0.55, dmg = 22, cd = 1.6, structDmg = 45, radius = 0.4, aggro = 3.5 },
}

return D
