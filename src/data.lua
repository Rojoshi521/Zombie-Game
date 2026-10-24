-- Content tables. Names, backgrounds and traits come from the design bible.
local D = {}

D.APTITUDES = {
  "Combat", "Engineering", "Scouting", "Scavenging", "Medicine",
  "Research", "Agriculture", "Fabrication", "Logistics", "Leadership",
}

-- The ten specialization groups, in hotkey order (1-9, then 0).
D.GROUPS = D.APTITUDES

D.GROUP_COLORS = {
  Combat = { 0.70, 0.24, 0.19 },
  Engineering = { 0.60, 0.62, 0.68 },
  Scouting = { 0.32, 0.56, 0.78 },
  Scavenging = { 0.82, 0.60, 0.26 },
  Medicine = { 0.45, 0.80, 0.62 },
  Research = { 0.62, 0.48, 0.85 },
  Agriculture = { 0.43, 0.60, 0.27 },
  Fabrication = { 0.80, 0.42, 0.20 },
  Logistics = { 0.36, 0.70, 0.72 },
  Leadership = { 0.88, 0.76, 0.40 },
}

-- What each group does at its buildings.
D.GROUP_WORKPLACE = {
  Combat = "drilling",
  Engineering = "patching walls and buildings",
  Scouting = "on watch",
  Scavenging = "sorting scrap",
  Medicine = "treating the wounded (faster healing)",
  Research = "studying (everyone learns faster)",
  Agriculture = "farming",
  Fabrication = "turning scrap into ammo",
  Logistics = "rationing (less food eaten)",
  Leadership = "at the HQ (all work goes faster)",
}

D.GROUP_LOADOUT = {
  Combat = "rifle", Engineering = "improvised", Scouting = "pistol", Scavenging = "improvised",
  Medicine = "pistol", Research = "improvised", Agriculture = "improvised", Fabrication = "improvised",
  Logistics = "improvised", Leadership = "pistol",
}

-- How far each survivor sees, in tiles. Scouts see much further.
D.VISION = 5
D.SCOUT_VISION = 8.5

-- Town buildings (assets/town, cut from the terrain sheets). size is the
-- footprint in tiles; loot names an entry in D.LOOT; solid buildings block.
D.TOWN_HOUSES = {
  { id = "blue_bungalow", name = "Small Blue Bungalow" },
  { id = "brick_townhouse", name = "Red Brick Townhouse" },
  { id = "ranch_house", name = "Beige Ranch House" },
  { id = "green_cottage", name = "Green Cottage" },
  { id = "split_level", name = "Yellow Split-Level" },
  { id = "white_farmhouse", name = "White Farmhouse" },
  { id = "brown_duplex", name = "Brown Duplex" },
  { id = "aframe_cabin", name = "Teal A-Frame Cabin" },
}
D.TOWN_SHOPS = {
  { id = "diner", name = "Diner", loot = "diner" },
  { id = "game_store", name = "Game Store", loot = "office" },
  { id = "grocery_store", name = "Grocery Store", loot = "grocery" },
  { id = "corner_store", name = "Corner Store", loot = "store" },
  { id = "hair_salon", name = "Hair Salon", loot = "office" },
  { id = "barber_shop", name = "Barber Shop", loot = "office" },
  { id = "vet_clinic", name = "Veterinary Clinic", loot = "clinic" },
  { id = "doctors_office", name = "Doctor's Office", loot = "clinic" },
  { id = "office_building", name = "Office Building", loot = "office" },
  { id = "high_rise", name = "High Rise", loot = "highrise" },
}
D.TOWN_SPECIALS = {
  { id = "police_station", name = "Police Station", loot = "police" },
  { id = "grade_school", name = "Grade School", loot = "school" },
  { id = "scrapyard", name = "Scrapyard", loot = "scrap" },
  { id = "factory", name = "Run-Down Factory", loot = "scrap" },
}
D.TOWN_LOTS = {
  { id = "grassy_field", name = "Grassy Field", flat = true },
  { id = "parking_lot", name = "Parking Lot", flat = true, loot = "jam" },
  { id = "pond", name = "Pond" },
  { id = "hill", name = "Hill" },
  { id = "dump", name = "Dump", loot = "dump" },
  { id = "traffic_jam", name = "Traffic Jam", loot = "jam" },
}
-- One of each per town, each taking the middle of a block.
D.TOWN_LANDMARKS = {
  { id = "jail", name = "Jail", size = 4, loot = "jail", views = { "front", "back" } },
  { id = "zoo", name = "Zoo", size = 3, loot = "zoo" },
  { id = "soccer_field", name = "Soccer Field", size = 3, flat = true },
}
D.TOWN_WRECKS = { "broken_car", "broken_truck", "car_on_fire", "truck_on_fire" }

-- Loot ranges { min, max }; rifle and pistol are chances of finding one.
D.LOOT = {
  house = { food = { 4, 12 }, scrap = { 2, 8 }, ammo = { 0, 8 }, pistol = 0.08 },
  diner = { food = { 15, 30 } },
  grocery = { food = { 25, 45 }, scrap = { 0, 5 } },
  store = { food = { 8, 18 }, ammo = { 0, 12 }, scrap = { 2, 6 } },
  office = { scrap = { 10, 22 }, food = { 0, 6 } },
  clinic = { food = { 4, 10 }, scrap = { 4, 10 } },
  highrise = { scrap = { 18, 32 }, food = { 6, 14 } },
  school = { food = { 8, 16 }, scrap = { 6, 12 } },
  police = { ammo = { 40, 80 }, rifle = 0.6, pistol = 0.7 },
  scrap = { scrap = { 35, 60 } },
  jail = { ammo = { 50, 90 }, scrap = { 10, 20 }, rifle = 0.9, pistol = 0.8 },
  zoo = { food = { 20, 40 } },
  dump = { scrap = { 20, 35 } },
  jam = { scrap = { 8, 18 }, ammo = { 0, 12 } },
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
}

-- Painted building sprites (made by tools/process_art.lua). ax, ay is the
-- pixel that sits on the centre of the footprint; scale converts the art to
-- world size.
D.SPRITES = {
  water_park_lifeguard_tower = { ax = 388, ay = 342, scale = 0.36, foot = 3 },
  garbage_compactor_truck = { ax = 398, ay = 211, scale = 0.36, foot = 3 },
  box_truck_armory = { ax = 400, ay = 340, scale = 0.31, foot = { 4, 3 } },
  salvage_garden = { ax = 400, ay = 290, scale = 0.36, foot = 4 },
  school_bus_barracks = { ax = 395, ay = 300, scale = 0.36, foot = 3 },
  hydroponic_shipping_containers = { ax = 422, ay = 280, scale = 0.36, foot = 3 },
  laundromat_sterilization_ward = { ax = 398, ay = 375, scale = 0.36, foot = 3 },
  derelict_arcade_lab = { ax = 365, ay = 352, scale = 0.36, foot = 3 },
  vending_machine_supply_wall = { ax = 398, ay = 375, scale = 0.36, foot = 3 },
  pizza_parlor_forge = { ax = 389, ay = 310, scale = 0.36, foot = 3 },
  tow_truck_workshop = { ax = 398, ay = 275, scale = 0.36, foot = 3 },
  trailer_blockade = { ax = 396, ay = 254, scale = 0.36, foot = 3 },
  excavator_graveyard = { ax = 395, ay = 290, scale = 0.36, foot = 3 },
  truck_stop = { ax = 396, ay = 356, scale = 0.36, foot = 3 },
  billboard_observation_nest = { ax = 348, ay = 344, scale = 0.36, foot = 3 },
  storm_chaser_van = { ax = 398, ay = 322, scale = 0.36, foot = 3 },
  airport_baggage_carousel = { ax = 398, ay = 295, scale = 0.36, foot = 3 },
  storage_lock_labyrinth = { ax = 398, ay = 346, scale = 0.36, foot = 3 },
  ice_cream_truck_pharmacy = { ax = 398, ay = 330, scale = 0.36, foot = 3 },
  bloodmobile_clinic = { ax = 398, ay = 323, scale = 0.36, foot = 3 },
  aquarium_containment_lab = { ax = 398, ay = 378, scale = 0.36, foot = 3 },
  bowling_alley_test_facility = { ax = 398, ay = 383, scale = 0.36, foot = 3 },
  pawnshop_gunsmith = { ax = 398, ay = 305, scale = 0.36, foot = 3 },
  soda_cannery_factory = { ax = 395, ay = 328, scale = 0.36, foot = 3 },
  parking_garage_stockpile = { ax = 398, ay = 377, scale = 0.36, foot = 3 },
  drive_thru_bank_vault = { ax = 398, ay = 370, scale = 0.36, foot = 3 },
  farmhouse = { ax = 398, ay = 271, scale = 0.48 },
  watertower = { ax = 392, ay = 336, scale = 0.48 },
  ferriswheel = { ax = 393, ay = 346, scale = 0.48 },
  casino = { ax = 393, ay = 322, scale = 0.48 },
  broadcast = { ax = 390, ay = 348, scale = 0.48 },
  cathedral = { ax = 390, ay = 333, scale = 0.48 },
  campus = { ax = 398, ay = 322, scale = 0.48 },
  coop = { ax = 398, ay = 280, scale = 0.48 },
}

-- Painted props (assets/props). Point props anchor (ax, ay) on the ground;
-- light is the lamp or flame position in image pixels.
-- Wall props are drawn as one vertical slice per tile: u0..u1 is the span of
-- the image that covers `cells` tiles, and the bottom edge of the wall runs
-- from (u0, base) with the given slope, sheared to the tile grid's 0.5.
D.PROPS = {
  watchtower = { ax = 112, ay = 240, scale = 0.45, light = { 30, 18, 1.3 } },
  crates = { ax = 175, ay = 148, scale = 0.3 },
  lamp = { ax = 84, ay = 205, scale = 0.42, light = { 84, 26, 1.0 } },
  firebarrel = { ax = 128, ay = 183, scale = 0.3, light = { 128, 110, 1.1 } },
  fence = { wall = true, u0 = 28, u1 = 262, cells = 3, base = 104, slope = 0.32 },
  gate = { wall = true, u0 = 20, u1 = 300, cells = 3, base = 135, slope = 0.15 },
}

D.ZOMBIES = {
  walker = { name = "Walker", hp = 45, speed = 0.8, dmg = 8, cd = 1.2, structDmg = 10, radius = 0.26, aggro = 4.5 },
  runner = { name = "Runner", hp = 28, speed = 1.75, dmg = 6, cd = 0.8, structDmg = 5, radius = 0.24, aggro = 6.5 },
  brute = { name = "Brute", hp = 240, speed = 0.55, dmg = 22, cd = 1.6, structDmg = 45, radius = 0.4, aggro = 3.5 },
}

return D
