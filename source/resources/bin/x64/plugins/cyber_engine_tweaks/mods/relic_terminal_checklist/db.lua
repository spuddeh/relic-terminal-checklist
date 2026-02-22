-- ======================================================================================
-- Mod Name: Relic Terminal Checklist
-- Author: Spuddeh
-- Description: Contains coordinates and detailed navigational descriptions.
-- Mod Version: 2.0.1
-- ======================================================================================

local RelicTerminalsDB = {
  {
    category = "Relic Terminals",
    entries = {
      {
        id = "ebm_petrochem_stadium",
        name = "EBM Petrochem Stadium",
        entityID = "11238500246117967073ULL",
        fast_travel = "EBM Petrochem Stadium",
        directions =
        "From the fast travel point, enter the stadium market and head North. Walk past the vehicle vendor and the tank. Continue up the stairs until you see three large statues of football players. The terminal is hidden in a small room directly behind these statues.",
        coords = { x = -1345.7985, y = -1947.3233, z = 75.8421, yaw = -135.9698 },
        requirement = "",
        district = "Dogtown",
        sub_district = "Stadium"
      },
      {
        id = "luxor_high_wellness_spa",
        name = "Luxor Hights Wellness Spa",
        entityID = "729892994426056981ULL",
        fast_travel = "Luxor Hights Wellness Spa",
        directions =
        "Located inside the Voodoo Boys base across from the fast travel point. Fight your way into the main building until you reach the large indoor pool area. The terminal is located in a side room/balcony overlooking the pool on the left-hand side.",
        coords = { x = -1457.4968, y = -2591.4650, z = 89.8936, yaw = 23.1138 },
        requirement = "",
        district = "Dogtown",
        sub_district = "Luxor Hights"
      },
      {
        id = "golden_pacific_apartments",
        name = "Golden Pacific (Apartments)",
        entityID = "12302642470407898797ULL",
        fast_travel = "Golden Pacific",
        directions =
        "Stand at the Heavy Hearts Club entrance and look directly across the street (North-West) to the ruined concrete building/construction site. Cross over and climb the stairs/rubble to the second floor. The terminal is tucked away on a wall at the end of the walkway bridge.",
        coords = { x = -1659.4294, y = -2208.6320, z = 51.0603, yaw = -46.0039 },
        requirement = "",
        district = "Dogtown",
        sub_district = "Golden Pacific"
      },
      {
        id = "golden_pacific_ruined_building",
        name = "Golden Pacific (Ruined Building)",
        entityID = "7657905188105447789ULL",
        fast_travel = "Golden Pacific",
        directions =
        "Head to the ruined overpass area near the Golden Pacific fast travel. Look for the destroyed building with 'Brainporium' signage. Climb the ruins to the roof area; the terminal is near a crashed Trauma Team AV wreckage.",
        coords = { x = -1671.2810, y = -2436.3069, z = 70.2024, yaw = 167.8522 },
        requirement = "",
        district = "Dogtown",
        sub_district = "Golden Pacific"
      },
      {
        id = "barricade",
        name = "Barricade",
        entityID = "16051267798654863494ULL",
        fast_travel = "Luxor Hights Wellness Spa",
        directions =
        "This terminal is underneath a large building with Voodoo Boys graffiti on the front. Take the southwest road from the fast travel point, in the underpass and on your left there will be a barricade with some Voodoo Boys graffiti. Jump over the barricade to find the terminal.",
        coords = { x = -1702.9615, y = -2715.5039, z = 83.4479, yaw = -131.4558 },
        requirement = "",
        district = "Dogtown",
        sub_district = "Luxor Hights"
      },
      {
        id = "abandoned_parking_structure",
        name = "Abandoned Parking Structure",
        entityID = "12490230065196808630ULL",
        fast_travel = "Golden Pacific",
        directions =
        "In the Golden Pacific Area, head up the stairs of the building with the large wireframe sphere on the roof. The data terminal should be behind the pile of debris next to a wall with turquoise graffiti on it. You can also access this terminal on the way to the crash site during the mission 'Hole in the Sky'.",
        coords = { x = -2043.1644, y = -2740.7751, z = 43.3569, yaw = -162.9972 },
        requirement = "",
        district = "Dogtown",
        sub_district = "Golden Pacific"
      },
      {
        id = "kress_street_hideout",
        name = "Kress Street Hideout",
        entityID = "14704035313715245020ULL",
        fast_travel = "Kress Street",
        directions =
        "This terminal is at the Kress Street hideout building itself. On the ground floor (street level), Facing the fast travel terminal, turn right and head towards the back wall. The terminal will be on your left.",
        coords = { x = -2235.5231, y = -2544.1362, z = 16.6110, yaw = 116.5821 },
        requirement = "",
        district = "Dogtown",
        sub_district = ""
      },
      {
        id = "barghest_forward_camp",
        name = "BARGHEST Forward Camp",
        entityID = "8899069361346253750ULL",
        fast_travel = "Kress Street",
        directions =
        "From Kress Street, follow the road to the 'Increased Criminal Activity' (green skulls) icon. Enter the tunnel base. The terminal is in a control room on the left. The door requires Tech Ability to open; otherwise, look for a floor grate nearby to crawl into the room from below.",
        coords = { x = -2375.7412, y = -2473.8325, z = 4.5791, yaw = 4.4566 },
        requirement = "Increased Criminal Activity",
        district = "Dogtown",
        sub_district = ""
      },
      {
        id = "terra_cognita_mass_driver",
        name = "Terra Cognita (Mass Driver)",
        entityID = "4231540305161490691ULL",
        fast_travel = "Terra Cognita",
        directions =
        "Enter the main hall of the Terra Cognita (Mass Driver) facility (marked by 'Increased Criminal Activity'). Clear the enemies, then go up the escalators to the upper floor. The terminal is inside a room on the left side of the upper walkway.",
        coords = { x = -2319.1052, y = -2947.8305, z = 123.4675, yaw = -41.5586 },
        requirement = "Increased Criminal Activity",
        district = "Dogtown",
        sub_district = "Terra Cognita"
      }
    }
  }
}

return RelicTerminalsDB
