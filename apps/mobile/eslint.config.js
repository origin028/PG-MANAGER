// https://docs.expo.dev/guides/using-eslint/
const { defineConfig } = require('eslint/config');
const expoConfig = require('eslint-config-expo/flat');

module.exports = defineConfig([
  expoConfig,
  {
    ignores: ['dist/*'],
  },
  {
    // HTML-entity rule does not apply to React Native <Text>; apostrophes render correctly.
    rules: { 'react/no-unescaped-entities': 'off' },
  },
]);
