# RPG Village - Phase One Plan
## Incorporating Tiny RPG Character Asset Pack (Zerie)

**Assets Source:** https://zerie.itch.io/tiny-rpg-character-asset-pack
**Tile Size:** 100×100 pixels
**License:** Personal & Commercial use allowed (credit appreciated but not required)

## Phase One Scope (Weeks 1-2)

### Core Systems Foundation
- [ ] **Save/Load System** - LocalStorage with version tracking
- [ ] **Inventory/Stats Framework** - Player Level/EXP/Gold/HP, basic item slots
- [ ] **Quest Skeleton** - Main questline structure, quest log UI stub

### Character Asset Integration
- [ ] **Soldier NPC** - Primary playable character / village guardian
  - Use: Free Soldier & Orc zip from pack
  - Animations: Idle, Walk (left/right), Attack, Hurt, Death
  - Tile: 100×100px, slice into game loop
  - Integration: Replace/augment existing `character` div in index.html

- [ ] **Orc NPC** - Villager/antagonist
  - Use: Free Soldier & Orc zip from pack
  - Animations: Same as Soldier
  - Integration: New building NPC (Barracks or Training Ground)

- [ ] **Projectile Sprites** - For combat/quest interactions
  - Use: 3 Arrow sprites + 6 Magic sprites from pack
  - Format: PNG spritesheets
  - Integration: New quest combat mechanics

### Map & Building Enhancements
- [ ] **Blacksmith Building** - New map building
  - Asset: Use Soldier sprite for blacksmith NPC
  - Interior: Basic workshop layout
  - Quest: "Repair the equipment" side quest

- [ ] **Well Building** - New map building
  - Asset: Decorative element, no NPC needed initially
  - Interaction: Click to restore quest progress (bonus)

- [ ] **Path System** - Connect new buildings
  - CSS ground modifications
  - Walkable terrain between buildings

### UI & Polish (Phase One Minimal)
- [ ] **Quest HUD Update** - Show main quest progress
- [ ] **Badge System** - Add 2-3 new badges for Phase One buildings
- [ ] **Transition Effects** - Ensure smooth building entry/exit

## Asset Integration Details

### Soldier Character (Free Zip)
```
File: Tiny RPG Character Asset Pack 01 v2.0 -Free Soldier&Orc.zip
Includes: Soldier + Orc animated characters
Animations per character:
  - Idle
  - Walk (left/right via flip)
  - Attack
  - Block (if shield-equipped)
  - Hurt
  - Death
  
Usage in RPG Portfolio:
  - Replace existing NPC sprites
  - Add to new buildings (Barracks, Blacksmith)
  - Character movement on map
```

### Orc Character (Free Zip)
```
Same file as above includes both Soldier and Orc
Orc variations: Basic Orc, Armored Orc, Elite Orc
Use cases: Villagers, enemies, quest targets
```

### Projectile Sprites
```
3 Arrow Sprites - for ranged quests
6 Magic Sprites - for spell-based interactions
Format: PNG files from pack
Integration: New combat or magic quest mechanics
```

## Technical Implementation

### Sprite Slicing (100×100 tiles)
Each character sheet contains multiple 100×100 cells. Phase One will:
1. Slice sheets into individual animation frames
2. CSS keyframe animations for idle/walk/attack
3. JavaScript state management for animation switching
4. Integration with existing game loop

### Character Class Structure (script.js enhancement)
```javascript
// New character data structure
const characterAssets = {
  soldier: {
    idle: [...frames],
    walk: [...frames],
    attack: [...frames],
    // ...other animations
  },
  orc: { /* same structure */ }
};
```

### Map Integration
- New buildings with `data-section` attributes
- NPC placement via CSS `left`/`top` percentages
- Click interactions for quest triggers

## Dependencies & Order

**Week 1:**
1. Download and extract asset pack
2. Slice spritesheets into frame arrays
3. Implement Save/Load System (localStorage)
4. Set up Inventory/Stats framework

**Week 2:**
1. Integrate Soldier & Orc NPCs into map
2. Add Blacksmith & Well buildings
3. Implement basic quest skeleton
4. Update quest HUD and badge system

## Success Criteria (Phase One Complete)
- [ ] Save/Load functional (3 save slots)
- [ ] Player stats display (Level/EXP/Gold/HP)
- [ ] Soldier NPC on map with walk animation
- [ ] Orc NPC in new building
- [ ] Blacksmith building accessible from map
- [ ] Well building on map
- [ ] 2 new badges unlockable
- [ ] Basic quest log showing main quest progress

## Notes
- Assets used under itch.io license (personal/commercial allowed)
- Credit to Zerie appreciated but not required
- Tile-based system (100×100px) aligns with existing CSS grid approach
- Existing game loop (`requestAnimationFrame`) can incorporate new sprite animations
- No redistribution of original asset files (modify/slice as needed for project)