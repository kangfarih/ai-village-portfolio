# RPG Village Expansion - Planning Document

## Overview
Expanding the existing "Farih's AI Village" RPG portfolio into a full village environment with new buildings, NPCs, quests, and systems.

---

## 1. World/Map Design

### Feature Ideas
- New buildings: Blacksmith, Library, Tavern, Farm, Well, Market, Church
- Procedural map layout with varied building positions
- Day/night cycle affecting which buildings are accessible
- Path system connecting buildings with walkable terrain
- Hidden areas discoverable through exploration
- Village entrance/exit to outside world map

### Technical Requirements
- Building data structure with positions, sizes, and section mappings
- Map collision detection or proximity-based interactions
- Dynamic building generation or placement system
- Background layer management (ground, objects, buildings)

### Priority: High
### Dependencies
- NPC System (buildings need NPCs)
- Quest System (buildings trigger quests)
- Interior Sections (new rooms for each building)

---

## 2. NPC System

### Feature Ideas
- New agent types: Library Keeper, Tavern Keeper, Blacksmith, Farmer, Merchant
- Conversation trees with multiple response paths
- NPC schedules (different locations/behaviors at different times)
- Gift/give system - give items to NPCs for rewards
- Reputation system - helping/hurting NPCs affects dialogue
- Dynamic speech bubbles with varying content

### Technical Requirements
- NPC data structure with name, role, position, dialogue tree
- Dialogue system - tree structure or JSON-based conversation flow
- Positioning system for multiple NPCs on map
- Modal or popup system for conversations
- Schedule/timer system for day/night cycles

### Priority: High
### Dependencies
- World/Map Design (NPCs need locations)
- Quest System (NPCs give/accept quests)
- Inventory/Stats (gifts and rewards)

---

## 3. Interior Sections

### Feature Ideas
- New interior rooms for each building:
  - Library (bookshelves, reading area, research terminals)
  - Tavern (tables, fireplace, bar counter, guests)
  - Blacksmith (anvil, tools, weapon rack, workbench)
  - Farm (crop plots, animal pens, storage)
  - Market (stalls, display goods, checkout counter)
- Interactive objects within interiors (books, items, crafting stations)
- Saving benches or save points in interiors
- Gallery walls displaying player achievements

### Technical Requirements
- Interior HTML structure per building (already partially exists)
- Object click handlers within interior spaces
- State tracking for interior-specific items/flags
- Transitions between map and interior (already exists)
- Dynamic content loading based on progression

### Priority: High
### Dependencies
- World/Map Design (interiors accessed from map buildings)
- Quest System (interiors may quest objectives)
- Inventory/Stats (items found/used in interiors)

---

## 4. Quest/Progression System

### Feature Ideas
- Main questline: "Restore the Village" with 8-10 steps
- Side quests from NPCs (fetch, delivery, repair tasks)
- Daily quests that refresh each "day"
- Quest tracking UI in HUD
- Quest rewards: items, gold, EXP, badge unlocks
- Quest log accessible from menu/HUD

### Technical Requirements
- Quest data structure: title, description, status, progress, rewards
- Quest tracking state (visited, completed, failed)
- Progress tracking logic (count items, talk to NPCs, etc.)
- HUD display for quest count/progress
- Quest completion checking logic

### Priority: High
### Dependencies
- NPC System (quest givers)
- Inventory/Stats (quest rewards go to inventory)
- Save/Load (quest progress persistence)
- World/Map Design (quest locations)

---

## 5. Inventory/Stats

### Feature Ideas
- Player stats: Level, EXP, Gold, HP
- Inventory system: Stackable items, limited slots
- Item types: Quest items, crafting materials, gifts for NPCs
- Stats screen in interior or menu
- Crafting system combining items
- Equipment slots (weapon, accessory)

### Technical Requirements
- Player state object with stats and inventory
- Item data structure (name, type, description, value)
- Inventory UI display
- Add/remove item logic
- Stat modification (level up, gain/lose HP)
- Local storage integration for inventory persistence

### Priority: Medium
### Dependencies
- Save/Load System (inventory persistence)
- Quest System (quest rewards go to inventory)
- NPC System (gifts and trading)

---

## 6. Save/Load System

### Feature Ideas
- Auto-save on key events (building entry, quest completion)
- Manual save via menu option
- Save slots (3 slots for different playthroughs)
- Export/import share codes
- Persistent storage of: position, visited sections, quest progress, inventory, reputation

### Technical Requirements
- LocalStorage service module
- Serialization of game state object
- Save/Load UI in title screen or interior menu
- Version tracking for future compatibility
- Error handling for corrupted storage

### Priority: High
### Dependencies
- All other systems (state to save)
- Inventory/Stats (items and stats to persist)
- Quest System (progress to persist)
- World/Map Design (position and visited areas)

---

## 7. Mobile Optimization

### Feature Ideas
- On-screen joystick for character movement
- Touch buttons for action (Enter/Interact, Back, Menu)
- Responsive building sizes adjusted for touch
- Virtual D-pad with configurable layout
- Touch gestures for inventory/quest menu

### Technical Requirements
- Rewrite touch controls for joystick pattern
- Mobile-friendly CSS (larger touch targets)
- Landscape/portrait orientation handling
- Reduced motion options for accessibility
- Performance optimization for mobile browsers

### Priority: High
### Dependencies
- Character Movement (rewrite for touch)
- Touch events (already partially exist)
- CSS responsive design

---

## 8. Accessibility

### Feature Ideas
- ARIA labels on all interactive elements
- Keyboard navigation full support (Tab order, Enter to select)
- Color contrast improvements (verify WCAG AA)
- Screen reader friendly descriptions
- Focus management between screens
- High contrast mode toggle
- Reduce motion option for animations

### Technical Requirements
- Semantic HTML where applicable
- ARIA attributes on buildings, NPCs, modals
- Focus trap logic for modals
- CSS media queries for contrast preferences
- Skip navigation links
- Test with screen readers

### Priority: Medium
### Dependencies
- All systems (need to add ARIA everywhere)
- Keyboard controls (already have some support)

---

## 9. Performance

### Feature Ideas
- Asset loading optimization - lazy load building interiors
- Object pooling for NPCs and particles
- Reduce DOM nodes - use CSS instead of JS-created elements
- Delta time-based movement for consistent speed
- Frame rate control option
- Background image optimization (compressed, WebP)

### Technical Requirements
- Performance monitoring (FPS display)
- Object recycling for NPCs/particles
- CSS will-change for animated elements
- RequestAnimationFrame optimization
- Asset preloading/prefetching
- Memory cleanup on exit

### Priority: Medium
### Dependencies
- All rendering-heavy systems (NPCs, particles, animations)

---

## Implementation Roadmap

### Phase 1 (Weeks 1-2): Core Systems
- Save/Load System
- Inventory/Stats framework
- Quest system skeleton

### Phase 2 (Weeks 3-4): World & NPCs
- New buildings (Blacksmith, Library, Tavern)
- 3-4 new NPC types
- Basic dialogue system

### Phase 3 (Weeks 5-6): Interiors & Polish
- Interior rooms for new buildings
- Interactive objects within interiors
- Quest log UI

### Phase 4 (Weeks 7-8): Optimization & Accessibility
- Mobile touch controls
- ARIA and keyboard nav
- Performance tuning
- Color contrast fixes

### Phase 5 (Weeks 9-10): Polish & Documentation
- Save/Load UI
- Documentation
- Testing and bug fixes

### Phase 6 (Weeks 11-12): Testing & Launch
- Cross-browser testing
- Mobile device testing
- Bug fixes
- Final performance review
- Deploy updated portfolio

---

## Task Delegation

Each domain can be delegated to subagents as separate TASKS.md items. Recommended delegation:

1. **World/Map Design** → Subagent A: New building definitions, map layout
2. **NPC System** → Subagent B: NPC data, dialogue trees, schedule logic
3. **Interior Sections** → Subagent C: New interior HTML/CSS, object interactions
4. **Quest/Progression** → Subagent D: Quest data, tracking, HUD updates
5. **Inventory/Stats** → Subagent E: Player state, item system, UI
6. **Save/Load** → Subagent F: LocalStorage service, UI, versioning
7. **Mobile Optimization** → Subagent G: Touch controls, responsive adjustments
8. **Accessibility** → Subagent H: ARIA, contrast, keyboard nav
9. **Performance** → Subagent I: Object pooling, optimization, testing