import * as PIXI from 'pixi.js';

export class GameScene extends PIXI.Container {
  private bgGraphics: PIXI.Graphics;
  private titleText: PIXI.Text;
  private subtitleText: PIXI.Text;
  private menuContainer: PIXI.Container;
  private contentContainer: PIXI.Container;
  private activeSection: string = 'home';

  constructor(app: PIXI.Application) {
    super();

    this.bgGraphics = new PIXI.Graphics();
    this.drawBackground(app.screen.width, app.screen.height);
    this.addChild(this.bgGraphics);

    this.titleText = new PIXI.Text('DEV PORTFOLIO // RPG WORLD', {
      fontFamily: 'Courier New',
      fontSize: 28,
      fontWeight: 'bold',
      fill: ['#00ffcc', '#0099ff'],
      dropShadow: true,
      dropShadowColor: '#000000',
      dropShadowBlur: 4,
      dropShadowDistance: 2,
    });
    this.titleText.anchor.set(0.5, 0);
    this.titleText.position.set(app.screen.width / 2, 30);
    this.addChild(this.titleText);

    this.subtitleText = new PIXI.Text('Interactive PixiJS + Tiny RPG Prototype', {
      fontFamily: 'Courier New',
      fontSize: 14,
      fill: '#aaaaaa',
    });
    this.subtitleText.anchor.set(0.5, 0);
    this.subtitleText.position.set(app.screen.width / 2, 70);
    this.addChild(this.subtitleText);

    this.menuContainer = new PIXI.Container();
    this.setupMenu(app);
    this.addChild(this.menuContainer);

    this.contentContainer = new PIXI.Container();
    this.contentContainer.position.set(app.screen.width / 2 - 300, 220);
    this.addChild(this.contentContainer);
    this.showSection('home');
  }

  private drawBackground(width: number, height: number) {
    this.bgGraphics.clear();
    this.bgGraphics.beginFill(0x1a1c23);
    this.bgGraphics.drawRect(0, 0, width, height);
    this.bgGraphics.endFill();

    this.bgGraphics.lineStyle(1, 0x2a2e3d, 0.5);
    const tileSize = 32;
    for (let x = 0; x < width; x += tileSize) {
      this.bgGraphics.moveTo(x, 0);
      this.bgGraphics.lineTo(x, height);
    }
    for (let y = 0; y < height; y += tileSize) {
      this.bgGraphics.moveTo(0, y);
      this.bgGraphics.lineTo(width, y);
    }
  }

  private setupMenu(app: PIXI.Application) {
    const sections = ['HOME', 'ABOUT', 'PROJECTS', 'CONTACT'];
    const startX = app.screen.width / 2 - (sections.length * 110) / 2;

    sections.forEach((sec, index) => {
      const btn = new PIXI.Container();
      btn.interactive = true;
      (btn as any).cursor = 'pointer';

      const bg = new PIXI.Graphics();
      bg.beginFill(0x2d3142);
      bg.lineStyle(2, 0x00ffcc);
      bg.drawRoundedRect(0, 0, 100, 40, 8);
      bg.endFill();
      btn.addChild(bg);

      const txt = new PIXI.Text(sec, {
        fontFamily: 'Courier New',
        fontSize: 14,
        fontWeight: 'bold',
        fill: 0xffffff,
      });
      txt.anchor.set(0.5);
      txt.position.set(50, 20);
      btn.addChild(txt);

      btn.position.set(startX + index * 115, 120);

      btn.on('pointerover', () => {
        bg.clear();
        bg.beginFill(0x00ffcc);
        bg.lineStyle(2, 0xffffff);
        bg.drawRoundedRect(0, 0, 100, 40, 8);
        bg.endFill();
        txt.style.fill = 0x111111;
      });

      btn.on('pointerout', () => {
        bg.clear();
        bg.beginFill(0x2d3142);
        bg.lineStyle(2, 0x00ffcc);
        bg.drawRoundedRect(0, 0, 100, 40, 8);
        bg.endFill();
        txt.style.fill = 0xffffff;
      });

      btn.on('pointertap', () => {
        this.showSection(sec.toLowerCase());
      });

      this.menuContainer.addChild(btn);
    });
  }

  private showSection(section: string) {
    this.activeSection = section;
    this.contentContainer.removeChildren();

    const frame = new PIXI.Graphics();
    frame.beginFill(0x0e1116, 0.9);
    frame.lineStyle(3, 0x00ffcc);
    frame.drawRoundedRect(0, 0, 600, 320, 12);
    frame.endFill();
    this.contentContainer.addChild(frame);

    let contentText = '';
    switch (section) {
      case 'home':
        contentText = 'WELCOME TO MY PORTFOLIO QUEST!\n\nI am a Full-Stack Software Engineer specializing in\nscalable web applications, interactive frontend experiences,\nand game-inspired UI design.\n\nUse the navigation above to explore my stats & quests.';
        break;
      case 'about':
        contentText = 'CHARACTER STATS:\n\n* Level: Senior Software Engineer\n* Class: Full-Stack Wizard / PixiJS Alchemist\n* Skills: TypeScript, React, Node.js, PixiJS, Python\n* Passions: Clean Architecture, Game Dev, Open Source';
        break;
      case 'projects':
        contentText = 'COMPLETED QUESTS (PROJECTS):\n\n1. Portfolio RPG Prototype (PixiJS + TS)\n2. Real-time Multiplayer Dungeon Crawler\n3. Microservice API Gateway & Event Bus\n4. Automated CI/CD Pipeline Dashboard';
        break;
      case 'contact':
        contentText = 'SEND A RAVEN (CONTACT):\n\n* Email: developer@rpg-portfolio.dev\n* GitHub: github.com/portfolio-hero\n* LinkedIn: linkedin.com/in/portfolio-hero\n\nReady for the next adventure together?';
        break;
    }

    const textObj = new PIXI.Text(contentText, {
      fontFamily: 'Courier New',
      fontSize: 15,
      fill: 0xdddddd,
      wordWrap: true,
      wordWrapWidth: 560,
      lineHeight: 22,
    });
    textObj.position.set(20, 20);
    this.contentContainer.addChild(textObj);
  }

  public resize(width: number, height: number) {
    this.drawBackground(width, height);
    this.titleText.position.set(width / 2, 30);
    this.subtitleText.position.set(width / 2, 70);
  }
}

