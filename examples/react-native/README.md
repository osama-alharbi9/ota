# React Native example

A bare React Native app with `ota-react-native` set up. It shows a label and which patch it's running, so you can see an update land.

```bash
npm install
ota init --force     # registers it on your server and rewrites ota.yaml
cd ios && pod install && cd ..
```

Then follow [docs/react-native.md](../../docs/react-native.md), or run `scripts/run_react_native_loop.sh android`.

It allows plain HTTP so it can reach a local server. Don't copy that part into a real app.
