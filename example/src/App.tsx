import { useCallback, useEffect, useState } from 'react';
import {
  FlatList,
  Pressable,
  SafeAreaView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { Image } from 'react-native-true-image';

const SIZE = 600;
const COUNT = 40;

// picsum.photos serves a stable image per id, so recycling and prefetch
// behaviour can be observed on real network loads.
const url = (id: number) => `https://picsum.photos/id/${id}/${SIZE}/${SIZE}`;
const ids = Array.from({ length: COUNT }, (_, i) => 10 + i * 3);

type Row = { id: number; label: string };

export default function App() {
  const [rows, setRows] = useState<Row[]>(() =>
    ids.map((id) => ({ id, label: `Cover ${id}` }))
  );
  const [prefetched, setPrefetched] = useState<boolean | null>(null);
  const [log, setLog] = useState<string[]>([]);
  const [heroId, setHeroId] = useState(ids[0] ?? 10);
  const [blur, setBlur] = useState(0);

  const push = useCallback(
    (line: string) => setLog((prev) => [line, ...prev].slice(0, 6)),
    []
  );

  useEffect(() => {
    Image.prefetch(ids.slice(0, 12).map(url)).then(setPrefetched);
  }, []);

  const shuffle = () =>
    setRows((prev) => [...prev].sort(() => Math.random() - 0.5));

  return (
    <SafeAreaView style={styles.root}>
      <View style={styles.hero}>
        <Image
          source={url(heroId)}
          blurRadius={blur}
          style={styles.heroImage}
          onLoad={(e) => push(`hero onLoad ${e.width}×${e.height}`)}
          onDisplay={() => push('hero onDisplay')}
          onDisplayEnd={() => push('hero onDisplayEnd')}
          onError={(e) => push(`hero onError ${e.error}`)}
        />
        <View style={styles.heroActions}>
          <Pressable
            style={styles.button}
            onPress={() =>
              setHeroId((h) => ids[(ids.indexOf(h) + 1) % ids.length] ?? h)
            }
          >
            <Text style={styles.buttonText}>Next cover</Text>
          </Pressable>
          <Pressable
            style={styles.button}
            onPress={() => setBlur((b) => (b === 0 ? 25 : b === 25 ? 60 : 0))}
          >
            <Text style={styles.buttonText}>Blur {blur}</Text>
          </Pressable>
          <Pressable style={styles.button} onPress={shuffle}>
            <Text style={styles.buttonText}>Shuffle list</Text>
          </Pressable>
        </View>
        <Text style={styles.status}>
          prefetch: {prefetched === null ? 'pending' : String(prefetched)}
        </Text>
        {log.map((line, i) => (
          <Text key={i} style={styles.log}>
            {line}
          </Text>
        ))}
      </View>
      <FlatList
        data={rows}
        keyExtractor={(row) => String(row.id)}
        numColumns={3}
        renderItem={({ item }) => (
          <View style={styles.cell}>
            <Image
              source={url(item.id)}
              recyclingKey={String(item.id)}
              style={styles.thumb}
            />
            <Text style={styles.caption}>{item.label}</Text>
          </View>
        )}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#111' },
  hero: { padding: 12, gap: 8 },
  heroImage: {
    width: '100%',
    aspectRatio: 16 / 9,
    borderRadius: 12,
    backgroundColor: '#222',
  },
  heroActions: { flexDirection: 'row', gap: 8 },
  button: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    backgroundColor: '#333',
    borderRadius: 8,
  },
  buttonText: { color: '#fff' },
  status: { color: '#9f9', fontVariant: ['tabular-nums'] },
  log: { color: '#aaa', fontSize: 12 },
  cell: { flex: 1 / 3, padding: 4 },
  thumb: {
    width: '100%',
    aspectRatio: 1,
    borderRadius: 8,
    backgroundColor: '#222',
  },
  caption: { color: '#888', fontSize: 11, marginTop: 2 },
});
