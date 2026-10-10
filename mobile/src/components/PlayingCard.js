import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity } from 'react-native';

const RED_SUITS = ['♥', '♦'];
const CARD_RATIO = 1.4;

export const getCardHeight = (width) => Math.round(width * CARD_RATIO);

const PlayingCard = ({
  card,
  width = 52,
  faceDown = false,
  selected = false,
  highlighted = false,
  wild = false,
  onPress,
  style,
  testID,
}) => {
  const size = { width, height: getCardHeight(width), borderRadius: Math.round(width * 0.12) };
  const Wrapper = onPress ? TouchableOpacity : View;
  const wrapperProps = onPress ? { onPress, activeOpacity: 0.8, testID } : { testID };

  if (faceDown || !card) {
    return (
      <Wrapper {...wrapperProps} style={[styles.card, styles.back, size, style]}>
        <View style={styles.backPattern} />
      </Wrapper>
    );
  }

  let color = '#212121';
  if (card.isJoker) color = '#6A1B9A';
  else if (RED_SUITS.includes(card.suit)) color = '#D32F2F';

  return (
    <Wrapper
      {...wrapperProps}
      style={[
        styles.card,
        size,
        highlighted && styles.highlighted,
        selected && styles.selected,
        style,
      ]}
    >
      <View style={styles.corner}>
        <Text style={[styles.rank, { color, fontSize: width * 0.32, lineHeight: width * 0.36 }]}>
          {card.isJoker ? '★' : card.value}
        </Text>
        {!card.isJoker && (
          <Text style={{ color, fontSize: width * 0.28, lineHeight: width * 0.3 }}>{card.suit}</Text>
        )}
      </View>

      <View style={styles.center}>
        {card.isJoker ? (
          <Text style={[styles.jokerText, { color, fontSize: width * 0.19 }]}>JOKER</Text>
        ) : (
          <Text style={{ color, fontSize: width * 0.48 }}>{card.suit}</Text>
        )}
      </View>

      {wild && !card.isJoker && (
        <View style={styles.wildBadge}>
          <Text style={styles.wildText}>J</Text>
        </View>
      )}
    </Wrapper>
  );
};

const styles = StyleSheet.create({
  card: {
    backgroundColor: '#fff',
    borderWidth: 1,
    borderColor: '#9E9E9E',
    overflow: 'hidden',
    elevation: 2,
  },
  selected: {
    borderColor: '#2196F3',
    borderWidth: 2,
    transform: [{ translateY: -10 }],
  },
  highlighted: {
    borderColor: '#FFC107',
    borderWidth: 2,
  },
  back: {
    backgroundColor: '#1565C0',
    borderColor: '#fff',
    padding: 4,
  },
  backPattern: {
    flex: 1,
    borderRadius: 3,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.6)',
    backgroundColor: '#1976D2',
  },
  corner: {
    position: 'absolute',
    top: 2,
    left: 4,
    alignItems: 'center',
  },
  rank: {
    fontWeight: 'bold',
  },
  center: {
    position: 'absolute',
    right: 3,
    bottom: 2,
    alignItems: 'flex-end',
  },
  jokerText: {
    fontWeight: 'bold',
  },
  wildBadge: {
    position: 'absolute',
    left: 3,
    bottom: 3,
    width: 14,
    height: 14,
    borderRadius: 7,
    backgroundColor: '#FFC107',
    alignItems: 'center',
    justifyContent: 'center',
  },
  wildText: {
    fontSize: 9,
    fontWeight: 'bold',
    color: '#212121',
  },
});

export default PlayingCard;
