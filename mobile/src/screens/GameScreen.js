import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  ScrollView,
  Modal,
  BackHandler,
  useWindowDimensions,
} from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { MaterialCommunityIcons as Icon } from '@expo/vector-icons';
import * as ScreenOrientation from 'expo-screen-orientation';
import useGameStore from '../store/gameStore';
import PlayingCard, { getCardHeight } from '../components/PlayingCard';
import { classifyMeld, evaluateHand, isWild, sortCards, formatCard, MELD_LABELS } from '../utils/rummy';
import { showAlert, confirmAction } from '../utils/dialogs';
import { COLORS } from '../utils/constants';

const GROUP_GAP = 12;
const HAND_PADDING = 16;

const OUTCOME_LABELS = {
  winner: 'Winner',
  lost: 'Lost',
  dropped: 'Dropped',
};

// Whole seconds left until a deadline, ticking while it is set
const useSecondsLeft = (deadline) => {
  const [now, setNow] = useState(Date.now());

  useEffect(() => {
    if (!deadline) return undefined;
    setNow(Date.now());
    const interval = setInterval(() => setNow(Date.now()), 500);
    return () => clearInterval(interval);
  }, [deadline]);

  return deadline ? Math.max(0, Math.ceil((deadline - now) / 1000)) : null;
};

const ActionButton = ({ label, icon, onPress, disabled, tone }) => (
  <TouchableOpacity
    onPress={onPress}
    disabled={disabled}
    style={[styles.actionButton, tone && styles[`${tone}Button`], disabled && styles.actionButtonDisabled]}
  >
    <Icon name={icon} size={16} color="#fff" />
    <Text style={styles.actionButtonText}>{label}</Text>
  </TouchableOpacity>
);

const OpponentChip = ({ player, isTurn, secondsLeft, showTotal }) => {
  let info = `${player.handCount} cards`;
  if (player.eliminated) info = 'Out';
  else if (player.status === 'dropped') info = 'Dropped';
  else if (!player.connected) info = 'Offline';
  if (showTotal) info += ` · ${player.totalScore} pts`;
  if (isTurn && secondsLeft != null) info += ` · ${secondsLeft}s`;

  const inactive = player.eliminated || player.status === 'dropped' || !player.connected;

  return (
    <View style={[styles.opponent, isTurn && styles.opponentTurn, inactive && styles.opponentInactive]}>
      <View style={styles.avatar}>
        <Text style={styles.avatarText}>{player.username.charAt(0).toUpperCase()}</Text>
      </View>
      <View>
        <Text style={styles.opponentName} numberOfLines={1}>{player.username}</Text>
        <Text style={styles.opponentInfo}>{info}</Text>
      </View>
    </View>
  );
};

const GameScreen = ({ navigation }) => {
  const { width, height } = useWindowDimensions();
  const insets = useSafeAreaInsets();
  const [selected, setSelected] = useState([]); // card ids
  const [busy, setBusy] = useState(false);

  const {
    gameId,
    gameState,
    gameStatus,
    roomCode,
    players,
    hand,
    groups,
    joker,
    playerId,
    isMyTurn,
    turnEndsAt,
    nextRoundAt,
    lastResult,
    notifications,
    connected,
    notify,
    drawCard,
    discardCard,
    declareWin,
    dropRound,
    setGroups,
    sortHand,
    leaveGame,
  } = useGameStore();

  useEffect(() => {
    // The table is laid out for landscape; the other screens are portrait
    ScreenOrientation.lockAsync(ScreenOrientation.OrientationLock.LANDSCAPE).catch(() => {});
    return () => {
      ScreenOrientation.lockAsync(ScreenOrientation.OrientationLock.PORTRAIT_UP).catch(() => {});
    };
  }, []);

  useEffect(() => {
    // Left the game, logged out, or the game is gone
    if (!gameId) {
      navigation.popToTop();
    }
  }, [gameId, navigation]);

  const confirmLeave = useCallback(() => {
    if (gameStatus === 'finished') {
      leaveGame();
      return;
    }
    confirmAction(
      'Leave game',
      'Leaving counts as a drop and you cannot rejoin this game.',
      'Leave',
      leaveGame
    );
  }, [gameStatus, leaveGame]);

  useEffect(() => {
    const subscription = BackHandler.addEventListener('hardwareBackPress', () => {
      confirmLeave();
      return true;
    });
    return () => subscription.remove();
  }, [confirmLeave]);

  const cardsById = useMemo(() => new Map(hand.map((card) => [card.id, card])), [hand]);

  useEffect(() => {
    // Forget selections for cards that are no longer in the hand
    setSelected((current) => current.filter((id) => cardsById.has(id)));
  }, [cardsById]);

  const melds = useMemo(
    () =>
      groups
        .map((ids) => {
          const cards = ids.map((id) => cardsById.get(id)).filter(Boolean);
          return { ids, cards, type: classifyMeld(cards, joker) };
        })
        .filter((meld) => meld.cards.length > 0),
    [groups, cardsById, joker]
  );

  const points = useMemo(
    () => evaluateHand(melds.map((meld) => meld.cards), joker).points,
    [melds, joker]
  );

  const playing = gameStatus === 'playing';
  const isPool = gameState?.gameType === 'pool';
  const me = players.find((player) => player.id === playerId);
  const opponents = players.filter((player) => player.id !== playerId);
  const inRound = playing && !!me && me.status === 'active' && !me.eliminated;
  const turnPhase = gameState?.turnPhase;
  const canDraw = inRound && isMyTurn && turnPhase === 'draw' && !busy;
  const canDiscard = inRound && isMyTurn && turnPhase === 'discard' && !busy;
  const nameOf = (id) => players.find((player) => player.id === id)?.username || 'Player';

  const secondsLeft = useSecondsLeft(playing ? turnEndsAt : null);
  const nextRoundSeconds = useSecondsLeft(gameStatus === 'round_over' ? nextRoundAt : null);

  // Card size follows the short side of the screen; cards in a group overlap as little as the width allows
  const cardWidth = Math.max(40, Math.min(58, Math.floor(Math.min(width, height) * 0.145)));
  const cardHeight = getCardHeight(cardWidth);
  const handWidth = width - insets.left - insets.right - HAND_PADDING * 2;
  const groupCount = Math.max(1, melds.length);
  const overlappedCards = hand.length - groupCount;
  const cardStep =
    overlappedCards > 0
      ? Math.max(
          cardWidth * 0.5,
          Math.min(
            cardWidth * 0.9,
            (handWidth - groupCount * cardWidth - (groupCount - 1) * GROUP_GAP) / overlappedCards
          )
        )
      : cardWidth;

  const run = async (action) => {
    setBusy(true);
    try {
      await action();
    } catch (error) {
      showAlert('Rummy', error.message);
    } finally {
      setBusy(false);
    }
  };

  const toggleCard = (cardId) => {
    setSelected((current) =>
      current.includes(cardId) ? current.filter((id) => id !== cardId) : [...current, cardId]
    );
  };

  const sortIds = (ids) =>
    sortCards(ids.map((id) => cardsById.get(id)).filter(Boolean)).map((card) => card.id);

  // Pull the selected cards out into a group of their own, where the first of them was
  const groupSelected = () => {
    const chosen = new Set(selected);
    const position = groups.findIndex((group) => group.some((id) => chosen.has(id)));
    const next = groups.map((group) => group.filter((id) => !chosen.has(id)));
    next.splice(position, 0, sortIds(selected));
    setGroups(next);
    setSelected([]);
  };

  const moveSelectedTo = (targetIndex) => {
    const chosen = new Set(selected);
    const target = melds[targetIndex].ids;
    setGroups(
      groups.map((group) => {
        const kept = group.filter((id) => !chosen.has(id));
        return group === target ? sortIds([...kept, ...selected]) : kept;
      })
    );
    setSelected([]);
  };

  const discardSelected = () =>
    run(async () => {
      await discardCard(selected[0]);
      setSelected([]);
    });

  const declareSelected = () => {
    const cardId = selected[0];
    const remaining = melds.map((meld) => meld.cards.filter((card) => card.id !== cardId));
    const { valid } = evaluateHand(remaining, joker);

    confirmAction(
      'Declare',
      valid
        ? `Finish with ${formatCard(cardsById.get(cardId))} and show your hand?`
        : 'Your groups are not a valid declaration yet. Declaring now costs 80 points.',
      'Declare',
      () =>
        run(async () => {
          const response = await declareWin(cardId);
          setSelected([]);
          if (!response.valid) {
            notify('error', 'Wrong declaration: you are out of this round with 80 points');
          }
        })
    );
  };

  const confirmDrop = () => {
    confirmAction(
      'Drop',
      'Give up this round? It costs 20 points before your first turn and 40 after.',
      'Drop',
      () => run(dropRound)
    );
  };

  if (!gameState) {
    return <SafeAreaView style={styles.container} />;
  }

  let statusText = '';
  if (!connected) statusText = 'Reconnecting…';
  else if (!playing) statusText = '';
  else if (me?.eliminated) statusText = 'You are out of the match';
  else if (me?.status === 'dropped') statusText = 'You are out of this round';
  else if (isMyTurn && turnPhase === 'draw') statusText = 'Your turn: draw from the deck or the open pile';
  else if (isMyTurn) statusText = 'Select a card, then Discard or Declare';
  else statusText = `Waiting for ${nameOf(gameState.currentPlayer)}`;

  const showResult = (gameStatus === 'round_over' || gameStatus === 'finished') && !!lastResult;
  let resultTitle = '';
  if (showResult) {
    if (gameStatus === 'finished') {
      if (!lastResult.matchWinner) resultTitle = 'Game over';
      else if (lastResult.matchWinner === playerId) resultTitle = 'You won!';
      else resultTitle = `${nameOf(lastResult.matchWinner)} won the game`;
    } else {
      const roundWinner = lastResult.winner === playerId ? 'You' : nameOf(lastResult.winner);
      resultTitle = `${roundWinner} won round ${lastResult.round}`;
    }
  }

  return (
    <SafeAreaView style={styles.container}>
      {/* Top bar */}
      <View style={styles.topBar}>
        <TouchableOpacity onPress={confirmLeave} style={styles.leaveButton}>
          <Icon name="exit-to-app" size={20} color="#fff" />
        </TouchableOpacity>
        <Text style={styles.roomText}>
          {roomCode} · {isPool ? `Pool ${gameState.poolLimit} · Round ${gameState.round}` : 'Points'}
        </Text>
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          style={styles.opponents}
          contentContainerStyle={styles.opponentsContent}
        >
          {opponents.map((player) => (
            <OpponentChip
              key={player.id}
              player={player}
              isTurn={playing && gameState.currentPlayer === player.id}
              secondsLeft={secondsLeft}
              showTotal={isPool}
            />
          ))}
        </ScrollView>
      </View>

      {/* Table */}
      <View style={styles.table}>
        <View style={styles.pile}>
          {joker ? (
            <PlayingCard card={joker} width={cardWidth} />
          ) : (
            <View style={[styles.emptyPile, { width: cardWidth, height: cardHeight }]} />
          )}
          <Text style={styles.pileLabel}>
            Joker{gameState.wildRank ? ` (${gameState.wildRank}s wild)` : ''}
          </Text>
        </View>

        <View style={styles.pile}>
          <PlayingCard
            faceDown
            testID="deck"
            width={cardWidth}
            onPress={canDraw ? () => run(() => drawCard(false)) : undefined}
            style={canDraw && styles.drawable}
          />
          <Text style={styles.pileLabel}>Deck ({gameState.deckCount})</Text>
        </View>

        <View style={styles.pile}>
          {gameState.discardTop ? (
            <PlayingCard
              card={gameState.discardTop}
              testID="open-pile"
              width={cardWidth}
              wild={isWild(gameState.discardTop, joker)}
              onPress={canDraw ? () => run(() => drawCard(true)) : undefined}
              style={canDraw && styles.drawable}
            />
          ) : (
            <View style={[styles.emptyPile, { width: cardWidth, height: cardHeight }]} />
          )}
          <Text style={styles.pileLabel}>Open pile</Text>
        </View>

        <View style={styles.statusBox}>
          <Text style={styles.statusText}>{statusText}</Text>
          {playing && secondsLeft != null && (
            <View style={styles.timer}>
              <Icon name="timer-outline" size={16} color={secondsLeft <= 5 ? '#FF8A80' : '#fff'} />
              <Text style={[styles.timerText, secondsLeft <= 5 && styles.timerTextLow]}>{secondsLeft}s</Text>
            </View>
          )}
          {isPool && me && <Text style={styles.totalText}>Your total: {me.totalScore}</Text>}
        </View>
      </View>

      {/* Hand */}
      <View style={styles.handArea}>
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.handContent}
        >
          {melds.map((meld, index) => {
            const canMoveHere = selected.length > 0 && !selected.every((id) => meld.ids.includes(id));
            let label = meld.cards.length >= 3 ? MELD_LABELS[meld.type] : ' ';
            if (canMoveHere) label = '+ Add';

            return (
              <View key={meld.ids[0]} style={index > 0 && { marginLeft: GROUP_GAP }}>
                <View style={styles.groupCards}>
                  {meld.cards.map((card, cardIndex) => (
                    <PlayingCard
                      key={card.id}
                      testID={`hand-card-${card.id}`}
                      card={card}
                      width={cardWidth}
                      wild={isWild(card, joker)}
                      selected={selected.includes(card.id)}
                      highlighted={card.id === gameState.lastDrawnId}
                      onPress={() => toggleCard(card.id)}
                      style={cardIndex > 0 && { marginLeft: cardStep - cardWidth }}
                    />
                  ))}
                </View>
                <TouchableOpacity
                  testID={`group-label-${index}`}
                  disabled={!canMoveHere}
                  onPress={() => moveSelectedTo(index)}
                  style={[
                    styles.groupLabel,
                    meld.cards.length >= 3 && meld.type === 'invalid' && styles.groupLabelInvalid,
                    meld.type !== 'invalid' && styles.groupLabelValid,
                    canMoveHere && styles.groupLabelTarget,
                  ]}
                >
                  <Text style={styles.groupLabelText} numberOfLines={1}>{label}</Text>
                </TouchableOpacity>
              </View>
            );
          })}
        </ScrollView>
      </View>

      {/* Actions */}
      <View style={styles.actions}>
        <Text style={styles.pointsText}>Points in hand: {points}</Text>
        <View style={styles.actionButtons}>
          <ActionButton
            label="Sort"
            icon="sort"
            onPress={() => {
              sortHand();
              setSelected([]);
            }}
            disabled={hand.length === 0}
          />
          <ActionButton label="Group" icon="group" onPress={groupSelected} disabled={selected.length < 2} />
          <ActionButton
            label="Discard"
            icon="arrow-down-bold"
            tone="primary"
            onPress={discardSelected}
            disabled={!canDiscard || selected.length !== 1}
          />
          <ActionButton
            label="Declare"
            icon="flag-checkered"
            tone="accent"
            onPress={declareSelected}
            disabled={!canDiscard || selected.length !== 1}
          />
          <ActionButton
            label="Drop"
            icon="close-circle-outline"
            tone="danger"
            onPress={confirmDrop}
            disabled={!canDraw}
          />
        </View>
      </View>

      {/* Notifications */}
      {notifications.length > 0 && (
        <View style={styles.notifications}>
          {notifications.slice(-2).map((notification) => (
            <View
              key={notification.id}
              style={[
                styles.notification,
                notification.type === 'error' && styles.errorNotification,
                notification.type === 'warning' && styles.warningNotification,
              ]}
            >
              <Text style={styles.notificationText}>{notification.message}</Text>
            </View>
          ))}
        </View>
      )}

      {/* Round / game result */}
      <Modal
        visible={showResult}
        transparent
        animationType="fade"
        supportedOrientations={['portrait', 'landscape']}
        onRequestClose={confirmLeave}
      >
        {showResult && (
          <View style={styles.modalBackdrop}>
            <View style={styles.modalCard}>
              <View style={styles.modalHeader}>
                <Icon name="trophy" size={22} color="#FFC107" />
                <Text style={styles.modalTitle}>{resultTitle}</Text>
              </View>

              <ScrollView style={styles.resultList}>
                {lastResult.players.map((row) => (
                  <View key={row.id} style={styles.resultRow}>
                    <View style={styles.resultHeader}>
                      <Text style={[styles.resultName, row.outcome === 'winner' && styles.resultWinner]}>
                        {row.username}
                        {row.id === playerId ? ' (you)' : ''}
                      </Text>
                      <Text style={styles.resultOutcome}>
                        {OUTCOME_LABELS[row.outcome]}
                        {isPool && row.eliminated ? ' · eliminated' : ''}
                      </Text>
                      <Text style={styles.resultPoints}>
                        {row.points} pts{isPool ? ` (total ${row.totalScore})` : ''}
                      </Text>
                    </View>
                    <Text style={styles.resultMelds}>
                      {row.melds.map((meld) => meld.cards.map(formatCard).join(' ')).join('   |   ')}
                    </Text>
                  </View>
                ))}
              </ScrollView>

              {gameStatus === 'finished' ? (
                <TouchableOpacity onPress={leaveGame} style={styles.modalButton}>
                  <Text style={styles.modalButtonText}>Back to Home</Text>
                </TouchableOpacity>
              ) : (
                <View style={styles.modalFooter}>
                  <Text style={styles.nextRoundText}>
                    {me?.eliminated ? 'You are out of the match. ' : ''}Next round in {nextRoundSeconds}s
                  </Text>
                  <TouchableOpacity onPress={confirmLeave}>
                    <Text style={styles.leaveLink}>Leave game</Text>
                  </TouchableOpacity>
                </View>
              )}
            </View>
          </View>
        )}
      </Modal>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: COLORS.table,
  },
  topBar: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 4,
    backgroundColor: COLORS.tableDark,
  },
  leaveButton: {
    padding: 6,
    marginRight: 8,
  },
  roomText: {
    color: '#C8E6C9',
    fontSize: 12,
    fontWeight: '600',
    marginRight: 12,
  },
  opponents: {
    flex: 1,
  },
  opponentsContent: {
    flexGrow: 1,
    justifyContent: 'flex-end',
    alignItems: 'center',
  },
  opponent: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 8,
    paddingVertical: 3,
    marginLeft: 8,
    borderRadius: 16,
    borderWidth: 2,
    borderColor: 'transparent',
    backgroundColor: 'rgba(255,255,255,0.12)',
  },
  opponentTurn: {
    borderColor: '#FFC107',
  },
  opponentInactive: {
    opacity: 0.5,
  },
  avatar: {
    width: 24,
    height: 24,
    borderRadius: 12,
    marginRight: 6,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: COLORS.secondary,
  },
  avatarText: {
    color: '#fff',
    fontSize: 12,
    fontWeight: 'bold',
  },
  opponentName: {
    color: '#fff',
    fontSize: 12,
    fontWeight: '600',
    maxWidth: 110,
  },
  opponentInfo: {
    color: '#C8E6C9',
    fontSize: 10,
  },
  table: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
  },
  pile: {
    alignItems: 'center',
    marginRight: 18,
  },
  pileLabel: {
    color: '#C8E6C9',
    fontSize: 10,
    marginTop: 3,
  },
  emptyPile: {
    borderRadius: 6,
    borderWidth: 1,
    borderStyle: 'dashed',
    borderColor: 'rgba(255,255,255,0.5)',
  },
  drawable: {
    borderColor: '#FFC107',
    borderWidth: 2,
  },
  statusBox: {
    flex: 1,
    alignItems: 'flex-end',
  },
  statusText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
    textAlign: 'right',
  },
  timer: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 4,
  },
  timerText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: 'bold',
    marginLeft: 4,
  },
  timerTextLow: {
    color: '#FF8A80',
  },
  totalText: {
    color: '#C8E6C9',
    fontSize: 11,
    marginTop: 2,
  },
  handArea: {
    backgroundColor: COLORS.tableDark,
  },
  handContent: {
    flexGrow: 1,
    justifyContent: 'center',
    paddingHorizontal: HAND_PADDING,
    paddingTop: 14, // room for a selected card to lift
    paddingBottom: 4,
  },
  groupCards: {
    flexDirection: 'row',
  },
  groupLabel: {
    marginTop: 3,
    paddingVertical: 1,
    paddingHorizontal: 4,
    borderRadius: 8,
    alignItems: 'center',
    backgroundColor: 'transparent',
  },
  groupLabelValid: {
    backgroundColor: '#2E7D32',
  },
  groupLabelInvalid: {
    backgroundColor: '#8D6E63',
  },
  groupLabelTarget: {
    backgroundColor: COLORS.secondary,
  },
  groupLabelText: {
    color: '#fff',
    fontSize: 10,
    fontWeight: '600',
  },
  actions: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 12,
    paddingVertical: 5,
    backgroundColor: COLORS.tableDark,
  },
  pointsText: {
    color: '#C8E6C9',
    fontSize: 12,
  },
  actionButtons: {
    flexDirection: 'row',
  },
  actionButton: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 7,
    marginLeft: 8,
    borderRadius: 16,
    backgroundColor: '#546E7A',
  },
  primaryButton: {
    backgroundColor: COLORS.secondary,
  },
  accentButton: {
    backgroundColor: '#EF6C00',
  },
  dangerButton: {
    backgroundColor: '#C62828',
  },
  actionButtonDisabled: {
    opacity: 0.35,
  },
  actionButtonText: {
    color: '#fff',
    fontSize: 12,
    fontWeight: '600',
    marginLeft: 4,
  },
  notifications: {
    position: 'absolute',
    top: 44,
    left: 0,
    right: 0,
    alignItems: 'center',
    pointerEvents: 'none',
  },
  notification: {
    backgroundColor: 'rgba(0,0,0,0.8)',
    paddingHorizontal: 14,
    paddingVertical: 6,
    borderRadius: 14,
    marginBottom: 4,
  },
  errorNotification: {
    backgroundColor: COLORS.error,
  },
  warningNotification: {
    backgroundColor: COLORS.warning,
  },
  notificationText: {
    color: '#fff',
    fontSize: 12,
  },
  modalBackdrop: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 16,
    backgroundColor: 'rgba(0,0,0,0.6)',
  },
  modalCard: {
    width: '100%',
    maxWidth: 560,
    maxHeight: '100%',
    padding: 16,
    borderRadius: 12,
    backgroundColor: '#fff',
  },
  modalHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 8,
  },
  modalTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    color: COLORS.text,
    marginLeft: 8,
  },
  resultList: {
    flexGrow: 0,
  },
  resultRow: {
    paddingVertical: 6,
    borderTopWidth: 1,
    borderTopColor: '#eee',
  },
  resultHeader: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  resultName: {
    flex: 1,
    fontSize: 14,
    fontWeight: '600',
    color: COLORS.text,
  },
  resultWinner: {
    color: COLORS.primary,
  },
  resultOutcome: {
    fontSize: 12,
    color: COLORS.textSecondary,
    marginRight: 12,
  },
  resultPoints: {
    fontSize: 14,
    fontWeight: 'bold',
    color: COLORS.text,
  },
  resultMelds: {
    fontSize: 12,
    color: COLORS.textSecondary,
    marginTop: 2,
  },
  modalButton: {
    marginTop: 12,
    paddingVertical: 10,
    borderRadius: 8,
    alignItems: 'center',
    backgroundColor: COLORS.primary,
  },
  modalButtonText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: 'bold',
  },
  modalFooter: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginTop: 12,
  },
  nextRoundText: {
    fontSize: 14,
    fontWeight: '600',
    color: COLORS.text,
  },
  leaveLink: {
    fontSize: 13,
    color: COLORS.error,
  },
});

export default GameScreen;
