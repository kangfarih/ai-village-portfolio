import * as PIXI from 'pixi.js';
import { GameScene } from './gameScene';

async function init() {
  const app = new PIXI.Application({
    resizeTo: window,
    backgroundColor: 0x111111,
    antialias: true,
  });

  const appContainer = document.getElementById('app');
  if (appContainer) {
    appContainer.appendChild(app.view as HTMLCanvasElement);
  }

  const gameScene = new GameScene(app);
  app.stage.addChild(gameScene);

  window.addEventListener('resize', () => {
    gameScene.resize(app.screen.width, app.screen.height);
  });

  console.log('PixiJS Portfolio Prototype initialized successfully!');
}

init();

