// ============================================
// FARIH'S QUEST - RPG Portfolio Game Logic
// ============================================

(function() {
    'use strict';

    // State
    const state = {
        started: false,
        currentView: 'title', // title, map, interior
        currentSection: null,
        characterX: 50, // percentage
        characterY: 65,
        visitedSections: new Set(),
        moving: false,
        moveDirX: 0, // -1 left, 0 none, 1 right
        moveDirY: 0  // -1 up, 0 none, 1 down
    };

    // DOM Elements
    const titleScreen = document.getElementById('title-screen');
    const mapView = document.getElementById('map-view');
    const character = document.getElementById('character');
    const transition = document.getElementById('transition');
    const questCount = document.getElementById('quest-count');
    const buildings = document.querySelectorAll('.building');
    const badges = document.querySelectorAll('.badge');
    const backBtns = document.querySelectorAll('.back-btn');

    // Constants
    const MOVE_SPEED = 0.5; // percentage per frame
    const MOVE_INTERVAL = 16; // ms (~60fps)
    const WORLD_PADDING = 5; // percentage from edges

    // ============================================
    // TITLE SCREEN
    // ============================================
    function startGame() {
        if (state.started) return;
        state.started = true;
        state.currentView = 'map';

        titleScreen.classList.remove('active');
        mapView.classList.add('active');

        // Position character in center
        updateCharacterPosition(50, 65);

        // Focus for keyboard input
        document.body.focus();
    }

    titleScreen.addEventListener('click', startGame);

    document.addEventListener('keydown', function(e) {
        if (e.key === 'Enter' && !state.started) {
            startGame();
        }
    });

    // ============================================
    // CHARACTER MOVEMENT
    // ============================================
    function updateCharacterPosition(x, y) {
        state.characterX = Math.max(WORLD_PADDING, Math.min(100 - WORLD_PADDING, x));
        state.characterY = Math.max(WORLD_PADDING, Math.min(100 - WORLD_PADDING, y));

        character.style.left = state.characterX + '%';
        character.style.top = state.characterY + '%';
    }

    function startMoving(dirX, dirY) {
        if (state.currentView !== 'map') return;
        state.moveDirX = dirX;
        state.moveDirY = dirY;
        state.moving = true;
        character.classList.add('walking');

        if (dirX === -1) {
            character.classList.add('facing-left');
        } else if (dirX === 1) {
            character.classList.remove('facing-left');
        }
    }

    function stopMoving() {
        state.moveDirX = 0;
        state.moveDirY = 0;
        state.moving = false;
        character.classList.remove('walking');
    }

    let moveInterval = null;

    function gameLoop() {
        if (state.moving && (state.moveDirX !== 0 || state.moveDirY !== 0)) {
            const newX = state.characterX + (state.moveDirX * MOVE_SPEED);
            const newY = state.characterY + (state.moveDirY * MOVE_SPEED);
            updateCharacterPosition(newX, newY);
            checkBuildingProximity();
        }
        requestAnimationFrame(gameLoop);
    }

    // Keyboard controls
    const keysPressed = {};

    document.addEventListener('keydown', function(e) {
        if (state.currentView !== 'map') return;

        keysPressed[e.key] = true;

        // Calculate direction from pressed keys
        let dirX = 0;
        let dirY = 0;
        if (keysPressed['ArrowLeft'] || keysPressed['a']) dirX = -1;
        if (keysPressed['ArrowRight'] || keysPressed['d']) dirX = 1;
        if (keysPressed['ArrowUp'] || keysPressed['w']) dirY = -1;
        if (keysPressed['ArrowDown'] || keysPressed['s']) dirY = 1;

        if (dirX !== 0 || dirY !== 0) {
            e.preventDefault();
            startMoving(dirX, dirY);
        }

        // Enter to interact
        if (e.key === 'Enter') {
            e.preventDefault();
            enterNearestBuilding();
        }

        // Escape to exit interior
        if (e.key === 'Escape' && state.currentView === 'interior') {
            exitInterior();
        }
    });

    document.addEventListener('keyup', function(e) {
        keysPressed[e.key] = false;

        // Check if any movement keys are still held
        const anyPressed = keysPressed['ArrowLeft'] || keysPressed['ArrowRight'] ||
                          keysPressed['a'] || keysPressed['d'] ||
                          keysPressed['ArrowUp'] || keysPressed['ArrowDown'] ||
                          keysPressed['w'] || keysPressed['s'];

        if (!anyPressed) {
            stopMoving();
        } else {
            // Recalculate direction from remaining pressed keys
            let dirX = 0;
            let dirY = 0;
            if (keysPressed['ArrowLeft'] || keysPressed['a']) dirX = -1;
            if (keysPressed['ArrowRight'] || keysPressed['d']) dirX = 1;
            if (keysPressed['ArrowUp'] || keysPressed['w']) dirY = -1;
            if (keysPressed['ArrowDown'] || keysPressed['s']) dirY = 1;
            startMoving(dirX, dirY);
        }
    });

    // Touch controls for mobile
    let touchStartX = 0;
    let touchStartY = 0;
    let touchMoving = false;

    mapView.addEventListener('touchstart', function(e) {
        touchStartX = e.touches[0].clientX;
        touchStartY = e.touches[0].clientY;
        touchMoving = true;
    });

    mapView.addEventListener('touchmove', function(e) {
        if (!touchMoving) return;
        e.preventDefault();

        const touchX = e.touches[0].clientX;
        const touchY = e.touches[0].clientY;
        const diffX = touchX - touchStartX;
        const diffY = touchY - touchStartY;

        let dirX = 0;
        let dirY = 0;

        if (Math.abs(diffX) > 10) dirX = diffX > 0 ? 1 : -1;
        if (Math.abs(diffY) > 10) dirY = diffY > 0 ? 1 : -1;

        if (dirX !== 0 || dirY !== 0) {
            startMoving(dirX, dirY);
        }
    });

    mapView.addEventListener('touchend', function() {
        touchMoving = false;
        stopMoving();
    });

    // Click to move
    mapView.addEventListener('click', function(e) {
        if (e.target.closest('.building')) return;
        if (e.target.closest('.back-btn')) return;

        const rect = mapView.getBoundingClientRect();
        const clickX = ((e.clientX - rect.left) / rect.width) * 100;
        const clickY = ((e.clientY - rect.top) / rect.height) * 100;

        // Calculate direction
        const dirX = clickX > state.characterX ? 1 : (clickX < state.characterX ? -1 : 0);
        const dirY = clickY > state.characterY ? 1 : (clickY < state.characterY ? -1 : 0);
        const distance = Math.hypot(clickX - state.characterX, clickY - state.characterY);
        const steps = Math.ceil(distance / MOVE_SPEED);

        stopMoving();
        startMoving(dirX, dirY);

        let step = 0;
        const moveTowards = setInterval(function() {
            step++;
            if (step >= steps) {
                clearInterval(moveTowards);
                stopMoving();
            }
        }, MOVE_INTERVAL);
    });

    // ============================================
    // BUILDING INTERACTION
    // ============================================
    function checkBuildingProximity() {
        buildings.forEach(building => {
            const section = building.dataset.section;
            const rect = building.getBoundingClientRect();
            const charRect = character.getBoundingClientRect();

            const distance = Math.hypot(
                (rect.left + rect.width/2) - (charRect.left + charRect.width/2),
                (rect.top + rect.height/2) - (charRect.top + charRect.height/2)
            );

            if (distance < 80) {
                building.style.filter = 'brightness(1.2)';
            } else {
                building.style.filter = '';
            }
        });
    }

    function enterNearestBuilding() {
        let nearest = null;
        let nearestDist = Infinity;

        buildings.forEach(building => {
            const rect = building.getBoundingClientRect();
            const charRect = character.getBoundingClientRect();

            const distance = Math.hypot(
                (rect.left + rect.width/2) - (charRect.left + charRect.width/2),
                (rect.top + rect.height/2) - (charRect.top + charRect.height/2)
            );

            if (distance < 120 && distance < nearestDist) {
                nearest = building;
                nearestDist = distance;
            }
        });

        if (nearest) {
            enterBuilding(nearest);
        }
    }

    buildings.forEach(building => {
        building.addEventListener('click', function(e) {
            e.stopPropagation();
            enterBuilding(this);
        });
    });

    function enterBuilding(building) {
        const section = building.dataset.section;

        // Transition effect
        transition.classList.add('active');

        setTimeout(function() {
            // Hide map, show interior
            mapView.classList.remove('active');
            const interior = document.getElementById('interior-' + section);
            if (interior) {
                interior.classList.add('active');
                state.currentView = 'interior';
                state.currentSection = section;

                // Mark as visited
                if (!state.visitedSections.has(section)) {
                    state.visitedSections.add(section);
                    unlockBadge(section);
                    updateQuestCount();
                }
            }

            setTimeout(function() {
                transition.classList.remove('active');
            }, 300);
        }, 400);
    }

    function exitInterior() {
        if (state.currentView !== 'interior') return;

        transition.classList.add('active');

        setTimeout(function() {
            // Hide interior, show map
            document.querySelectorAll('.interior').forEach(el => {
                el.classList.remove('active');
            });
            mapView.classList.add('active');
            state.currentView = 'map';
            state.currentSection = null;

            setTimeout(function() {
                transition.classList.remove('active');
            }, 300);
        }, 400);
    }

    backBtns.forEach(btn => {
        btn.addEventListener('click', exitInterior);
    });

    // ============================================
    // ACHIEVEMENTS
    // ============================================
    function unlockBadge(section) {
        const badge = document.querySelector('.badge[data-badge="' + section + '"]');
        if (badge && !badge.classList.contains('unlocked')) {
            badge.classList.add('unlocked');

            // Flash effect
            badge.style.transform = 'scale(1.3)';
            setTimeout(function() {
                badge.style.transform = '';
            }, 300);
        }
    }

    function updateQuestCount() {
        questCount.textContent = state.visitedSections.size;
    }

    // ============================================
    // SKILL BAR ANIMATION
    // ============================================
    function animateSkillBars() {
        const skillBars = document.querySelectorAll('.bar-fill');
        skillBars.forEach(bar => {
            const width = bar.style.width;
            bar.style.width = '0%';
            setTimeout(function() {
                bar.style.width = width;
            }, 100);
        });
    }

    // Observe when skills section becomes visible
    const skillsSection = document.getElementById('interior-skills');
    if (skillsSection) {
        const observer = new MutationObserver(function(mutations) {
            mutations.forEach(function(mutation) {
                if (mutation.target.classList.contains('active')) {
                    animateSkillBars();
                }
            });
        });
        observer.observe(skillsSection, { attributes: true, attributeFilter: ['class'] });
    }

    // Observe when AI Lab section becomes visible
    const aiLabSection = document.getElementById('interior-ai-lab');
    if (aiLabSection) {
        const observer = new MutationObserver(function(mutations) {
            mutations.forEach(function(mutation) {
                if (mutation.target.classList.contains('active')) {
                    animateAiLab();
                }
            });
        });
        observer.observe(aiLabSection, { attributes: true, attributeFilter: ['class'] });
    }

    function animateAiLab() {
        const bars = document.querySelectorAll('.ai-lab .agent-bar-fill');
        bars.forEach(bar => {
            const width = bar.style.width;
            bar.style.width = '0%';
            setTimeout(function() {
                bar.style.width = width;
            }, 200);
        });

        // Animate agent cards
        const cards = document.querySelectorAll('.ai-agent-card');
        cards.forEach((card, i) => {
            card.style.opacity = '0';
            card.style.transform = 'translateY(20px)';
            setTimeout(function() {
                card.style.opacity = '1';
                card.style.transform = 'translateY(0)';
            }, 100 + i * 100);
        });
    }

    // ============================================
    // AI AGENT NPCs
    // ============================================
    const npcs = document.querySelectorAll('.npc');
    const npcModal = document.getElementById('npc-modal');
    const npcModalName = document.getElementById('npc-modal-name');
    const npcModalRole = document.getElementById('npc-modal-role');
    const npcModalDesc = document.getElementById('npc-modal-desc');
    const npcModalSkills = document.getElementById('npc-modal-skills');
    const npcModalStatus = document.getElementById('npc-modal-status');
    const npcModalAvatar = document.getElementById('npc-modal-avatar');
    const npcModalClose = document.querySelector('.npc-modal-close');

    const npcData = {
        codebot: {
            name: 'CodeBot',
            role: 'Frontend Engineering Agent',
            emoji: '🔍',
            desc: 'Production React/Next.js + TypeScript, Redux Toolkit, Tailwind — Appfuxion & Creatella experience. SSR/CSR, routing, performance.',
            skills: ['React', 'Next.js', 'TypeScript', 'Redux Toolkit'],
            messages: [
                'Shipping Next.js SSR...',
                'Redux Toolkit slice...',
                'Tailwind responsive...',
                'MSAL auth flow...',
                'PR approved ✓',
                'Vitest green...',
                'Performance tuned...'
            ]
        },
        docbot: {
            name: 'DocWriter',
            role: 'Delivery & Quality Agent',
            emoji: '📝',
            desc: 'Git/GitHub/GitLab/Bitbucket workflows, CI/CD basics, Vitest + Testing Library, ESLint + SonarQube gates.',
            skills: ['Git', 'CI/CD', 'Vitest', 'ESLint'],
            messages: [
                'Branching feature/ui...',
                'Pushing to GitHub...',
                'CI pipeline running...',
                'ESLint clean ✓',
                'SonarQube gate passed...',
                'Vitest suite green...',
                'Merging to main...'
            ]
        },
        databot: {
            name: 'DataBot',
            role: 'Realtime & Backend Agent',
            emoji: '📊',
            desc: 'Socket.IO + SSE streaming, Node.js + Express, MongoDB/PostgreSQL, REST APIs.',
            skills: ['Socket.IO', 'SSE', 'Node.js', 'REST'],
            messages: [
                'Streaming via Socket.IO...',
                'SSE channel open...',
                'Express route wired...',
                'REST API responding...',
                'MongoDB synced ✓',
                'Postgres query tuned...',
                'Realtime update pushed...'
            ]
        },
        designbot: {
            name: 'DesignBot',
            role: 'Mobile & Games Agent',
            emoji: '🎨',
            desc: 'React Native cross-platform apps (MySLife, Ragasukma), Unity + C# AR/games (First4Figures), Inkscape/Illustrator assets.',
            skills: ['React Native', 'Unity', 'AR', 'Inkscape'],
            messages: [
                'Building MySLife UI...',
                'Ragasukma reader view...',
                'AR scene placed...',
                'Unity build success ✓',
                'C# mechanic wired...',
                'Inkscape asset exported...',
                'Play Store ready...'
            ]
        },
        chatbot: {
            name: 'ChatBot',
            role: 'Auth & Support Agent',
            emoji: '💬',
            desc: 'Azure AD MSAL sign-in/token flows, jQuery/Bootstrap legacy compat, Safari/iOS fixes from Interactive Video freelance.',
            skills: ['MSAL', 'Azure AD', 'jQuery', 'Bootstrap'],
            messages: [
                'MSAL sign-in started...',
                'Azure AD token acquired...',
                'Token refresh silent...',
                'Session secured ✓',
                'jQuery hotspot wired...',
                'Bootstrap layout fixed...',
                'Safari/iOS fix shipped...'
            ]
        }
    };

    // NPC click handler
    npcs.forEach(npc => {
        npc.addEventListener('click', function(e) {
            e.stopPropagation();
            const npcKey = this.dataset.npc;
            const data = npcData[npcKey];
            if (!data) return;

            npcModalAvatar.textContent = data.emoji;
            npcModalName.textContent = data.name;
            npcModalRole.textContent = data.role;
            npcModalDesc.textContent = data.desc;
            npcModalSkills.innerHTML = data.skills.map(s =>
                '<span class="npc-skill-tag">' + s + '</span>'
            ).join('');
            npcModalStatus.textContent = 'Active - ' + data.messages[0];

            npcModal.classList.add('active');
        });
    });

    // Close modal
    if (npcModalClose) {
        npcModalClose.addEventListener('click', function() {
            npcModal.classList.remove('active');
        });
    }

    npcModal.addEventListener('click', function(e) {
        if (e.target === npcModal) {
            npcModal.classList.remove('active');
        }
    });

    // NPC auto-movement
    const npcPositions = {};
    npcs.forEach(npc => {
        const key = npc.dataset.npc;
        npcPositions[key] = {
            x: parseFloat(npc.style.left),
            y: parseFloat(npc.style.top),
            targetX: parseFloat(npc.style.left),
            targetY: parseFloat(npc.style.top),
            speed: 0.03,
            moveTimer: 0,
            messageIndex: 0
        };
    });

    // Cycle NPC messages
    function cycleNpcMessages() {
        npcs.forEach(npc => {
            const key = npc.dataset.npc;
            const data = npcData[key];
            const pos = npcPositions[key];
            if (!data || !pos) return;

            pos.messageIndex = (pos.messageIndex + 1) % data.messages.length;
            const bubble = npc.querySelector('.npc-bubble');
            if (bubble) {
                bubble.textContent = data.messages[pos.messageIndex];
            }
        });
    }

    setInterval(cycleNpcMessages, 3000);

    // NPC movement loop
    function updateNpcs() {
        if (state.currentView !== 'map') {
            requestAnimationFrame(updateNpcs);
            return;
        }

        npcs.forEach(npc => {
            const key = npc.dataset.npc;
            const pos = npcPositions[key];
            if (!pos) return;

            // Pick new target periodically
            pos.moveTimer++;
            if (pos.moveTimer > 120 + Math.random() * 180) {
                pos.moveTimer = 0;
                // Random position within bounds
                pos.targetX = 10 + Math.random() * 75;
                pos.targetY = 25 + Math.random() * 55;
            }

            // Move towards target
            const dx = pos.targetX - pos.x;
            const dy = pos.targetY - pos.y;
            const dist = Math.sqrt(dx * dx + dy * dy);

            if (dist > 0.5) {
                pos.x += (dx / dist) * pos.speed * 50;
                pos.y += (dy / dist) * pos.speed * 50;
                npc.classList.add('walking');

                // Flip based on direction
                if (dx < 0) {
                    npc.style.transform = 'scaleX(-1)';
                } else {
                    npc.style.transform = 'scaleX(1)';
                }
            } else {
                npc.classList.remove('walking');
            }

            npc.style.left = pos.x + '%';
            npc.style.top = pos.y + '%';
        });

        requestAnimationFrame(updateNpcs);
    }

    // ============================================
    // INITIALIZATION
    // ============================================
    function init() {
        // Start game loop
        requestAnimationFrame(gameLoop);

        // Start NPC movement
        requestAnimationFrame(updateNpcs);

        // Prevent default on arrow keys
        document.addEventListener('keydown', function(e) {
            if (['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.key)) {
                e.preventDefault();
            }
        });
    }

    init();

})();
