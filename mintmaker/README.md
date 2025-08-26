# MintMaker extensible configurations

You can use these configurations in your repositories by using the `extends` key in your
`renovate.json` configuration. Replace the `mintmaker/<file>` with the file from which you'd like 
to extend your configuration (without the `.json` extension):

```json
"extends": ["github>stolostron/konflux-build-catalog//mintmaker/default"]
```

Documentation:
- [Renovate Presets](https://docs.renovatebot.com/config-presets/#github-hosted-presets)
