import { Options as ElectronStoreOptions } from 'electron-store';

// Extend the ElectronStore interface to include the methods/properties we're using
declare module 'electron-store' {
  export interface ElectronStore<T> {
    // Data access methods
    get<K extends keyof T>(key: K): T[K];
    get<K extends keyof T, D>(key: K, defaultValue: D): T[K] | D;
    get(): T;
    set<K extends keyof T>(key: K, value: T[K]): void;
    set(object: Partial<T>): void;
    has<K extends keyof T>(key: K): boolean;
    delete<K extends keyof T>(key: K): void;
    clear(): void;
    // Data access property
    store: T;
  }

  export default class Store<T> implements ElectronStore<T> {
    constructor(options?: ElectronStoreOptions);
    get<K extends keyof T>(key: K): T[K];
    get<K extends keyof T, D>(key: K, defaultValue: D): T[K] | D;
    get(): T;
    set<K extends keyof T>(key: K, value: T[K]): void;
    set(object: Partial<T>): void;
    has<K extends keyof T>(key: K): boolean;
    delete<K extends keyof T>(key: K): void;
    clear(): void;
    readonly store: T;
  }
} 