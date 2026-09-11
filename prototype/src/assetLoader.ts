import { Assets } from 'pixi.js';

export interface GameAssets {
  [key: string]: any;
}

export async function loadGameAssets(): Promise<GameAssets> {
  try {
    return {};
  } catch (e) {
    console.warn('Asset loading warning, using fallback procedural sprites', e);
    return {};
  }
}

