module.exports = function(api) {
  api.cache(true);
  return {
    // The web bundle pulls in ESM builds that use `import.meta.env` (zustand does), which is a
    // syntax error in Metro's classic-script output. The preset option rewrites every `import.meta`.
    presets: [['babel-preset-expo', { unstable_transformImportMeta: true }]],
    // Babel needs to transform any `import.meta` expressions, especially when building
    // the web bundle. Expo uses `import.meta.env` under the hood for public vars, so
    // keep the transform plugin enabled to avoid runtime syntax errors.
    plugins: ['babel-plugin-transform-import-meta'],
  };
};
