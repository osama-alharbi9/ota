import { useEffect, useState } from 'react';
import { Button, Image, StatusBar, StyleSheet, Text, View } from 'react-native';
import { checkForUpdate, getState, type OtaState } from 'ota-react-native';

// Change this, run `ota patch react-native`, then restart the app twice: once to
// download the patch and once to run it.
const LABEL = 'RELEASE v1';

console.log(`OTA_EXAMPLE_LABEL=${LABEL}`);

export default function App() {
  const [state, setState] = useState<OtaState | null>(null);
  const [check, setCheck] = useState('');

  useEffect(() => {
    getState().then(setState);
  }, []);

  return (
    <View style={styles.screen}>
      <StatusBar barStyle="dark-content" />
      <Image source={require('./assets/ota.png')} style={styles.logo} />
      <Text style={styles.label} testID="label">
        {LABEL}
      </Text>
      <Text style={styles.detail}>Release {state?.releaseVersion ?? '...'}</Text>
      <Text style={styles.detail}>Patch {state?.bootedPatch ?? 'none'}</Text>
      <Text style={styles.detail}>Next launch {state?.nextPatch ?? 'no change'}</Text>
      <Button
        title="Check for update"
        onPress={async () => {
          const result = await checkForUpdate();
          setCheck(result.status);
          setState(await getState());
        }}
      />
      <Text style={styles.detail}>{check}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: '#fff' },
  logo: { width: 72, height: 72, marginBottom: 24 },
  label: { fontSize: 32, fontWeight: '700', marginBottom: 16, color: '#111' },
  detail: { fontSize: 16, marginBottom: 6, color: '#555' },
});
