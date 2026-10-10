import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TextInput,
  TouchableOpacity,
  ScrollView,
  ActivityIndicator,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Card, Button, Title, Avatar } from 'react-native-paper';
import { MaterialCommunityIcons as Icon } from '@expo/vector-icons';
import useAuthStore from '../store/authStore';
import { showAlert, confirmAction } from '../utils/dialogs';

const ProfileScreen = ({ navigation }) => {
  const { user, logout, fetchProfile, updateProfile } = useAuthStore();
  const [loading, setLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);

  useEffect(() => {
    // Stats (games played / won) only come with the profile, so refresh it once on opening
    const load = async () => {
      await fetchProfile();
      setLoading(false);
    };
    load();
  }, []);

  const [isEditing, setIsEditing] = useState(false);
  const [editedUser, setEditedUser] = useState({ username: '', email: '' });

  const startEditing = () => {
    setEditedUser({ username: user.username || '', email: user.email || '' });
    setIsEditing(true);
  };

  const handleSaveProfile = async () => {
    // Accounts registered with a phone number may leave the email empty
    if (!editedUser.username.trim() || (!editedUser.email.trim() && !user.phone)) {
      showAlert('Error', 'Please fill in all fields');
      return;
    }

    setIsSaving(true);
    try {
      await updateProfile({
        username: editedUser.username.trim(),
        email: editedUser.email.trim(),
      });
      setIsEditing(false);
      showAlert('Success', 'Profile updated successfully!');
    } catch (error) {
      showAlert('Error', error.message);
    } finally {
      setIsSaving(false);
    }
  };

  const handleLogout = () => {
    confirmAction('Logout', 'Are you sure you want to logout?', 'Logout', async () => {
      await logout();
      navigation.popToTop();
    });
  };

  const totalGames = user?.totalGames || 0;
  const gamesWon = user?.gamesWon || 0;
  const winRate = totalGames > 0 ? ((gamesWon / totalGames) * 100).toFixed(1) : 0;

  if (loading || !user) {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.centered}>
          <ActivityIndicator size="large" color="#4CAF50" />
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView contentContainerStyle={styles.scrollContent}>
        {/* Header */}
        <View style={styles.header}>
          <TouchableOpacity
            onPress={() => navigation.goBack()}
            style={styles.backButton}
          >
            <Icon name="arrow-left" size={24} color="#333" />
          </TouchableOpacity>
          <Title style={styles.title}>Profile</Title>
          <TouchableOpacity
            onPress={() => (isEditing ? setIsEditing(false) : startEditing())}
            style={styles.editButton}
          >
            <Icon
              name={isEditing ? "close" : "pencil"}
              size={24}
              color="#4CAF50"
            />
          </TouchableOpacity>
        </View>

        {/* Avatar Section */}
        <View style={styles.avatarSection}>
          <Avatar.Text
            size={80}
            label={user?.username?.charAt(0)?.toUpperCase() || '?'}
            style={styles.avatar}
          />
          <Text style={styles.username}>{user?.username || ''}</Text>
          <Text style={styles.email}>{user?.email || user?.phone || ''}</Text>
        </View>

        {/* Stats Cards */}
        <View style={styles.statsContainer}>
          <Card style={styles.statCard}>
            <Card.Content style={styles.statContent}>
              <Icon name="trophy" size={30} color="#FFD700" />
              <Text style={styles.statNumber}>{gamesWon}</Text>
              <Text style={styles.statLabel}>Games Won</Text>
            </Card.Content>
          </Card>

          <Card style={styles.statCard}>
            <Card.Content style={styles.statContent}>
              <Icon name="cards" size={30} color="#2196F3" />
              <Text style={styles.statNumber}>{totalGames}</Text>
              <Text style={styles.statLabel}>Total Games</Text>
            </Card.Content>
          </Card>

          <Card style={styles.statCard}>
            <Card.Content style={styles.statContent}>
              <Icon name="wallet" size={30} color="#4CAF50" />
              <Text style={styles.statNumber}>₹{user.wallet}</Text>
              <Text style={styles.statLabel}>Wallet</Text>
            </Card.Content>
          </Card>

          <Card style={styles.statCard}>
            <Card.Content style={styles.statContent}>
              <Icon name="percent" size={30} color="#FF9800" />
              <Text style={styles.statNumber}>{winRate}%</Text>
              <Text style={styles.statLabel}>Win Rate</Text>
            </Card.Content>
          </Card>
        </View>

        {/* Edit Profile Section */}
        {isEditing && (
          <Card style={styles.editCard}>
            <Card.Content>
              <Title style={styles.editTitle}>Edit Profile</Title>

              <Text style={styles.inputLabel}>Username</Text>
              <TextInput
                style={styles.input}
                value={editedUser.username}
                onChangeText={(text) =>
                  setEditedUser({ ...editedUser, username: text })
                }
                placeholder="Username"
                maxLength={20}
              />

              <Text style={styles.inputLabel}>Email</Text>
              <TextInput
                style={styles.input}
                value={editedUser.email}
                onChangeText={(text) =>
                  setEditedUser({ ...editedUser, email: text })
                }
                placeholder="Email"
                keyboardType="email-address"
                autoCapitalize="none"
              />

              <View style={styles.buttonRow}>
                <Button
                  mode="outlined"
                  onPress={() => setIsEditing(false)}
                  style={styles.cancelButton}
                >
                  Cancel
                </Button>
                <Button
                  mode="contained"
                  onPress={handleSaveProfile}
                  loading={isSaving}
                  disabled={isSaving}
                  style={styles.saveButton}
                >
                  Save
                </Button>
              </View>
            </Card.Content>
          </Card>
        )}

        {/* Account Info */}
        <Card style={styles.infoCard}>
          <Card.Content>
            <Title style={styles.infoTitle}>Account Information</Title>

            <View style={styles.infoRow}>
              <Icon name="calendar" size={20} color="#666" />
              <View style={styles.infoContent}>
                <Text style={styles.infoLabel}>Member Since</Text>
                <Text style={styles.infoValue}>
                  {new Date(user.created_at).toLocaleDateString('en-US', {
                    year: 'numeric',
                    month: 'long',
                    day: 'numeric',
                  })}
                </Text>
              </View>
            </View>

            <View style={styles.infoRow}>
              <Icon name="account-check" size={20} color="#666" />
              <View style={styles.infoContent}>
                <Text style={styles.infoLabel}>Account Status</Text>
                <Text style={styles.infoValue}>Active</Text>
              </View>
            </View>
          </Card.Content>
        </Card>

        {/* Logout Button */}
        <View style={styles.logoutContainer}>
          <Button
            mode="outlined"
            onPress={handleLogout}
            style={styles.logoutButton}
            icon="logout"
            textColor="#F44336"
          >
            Logout
          </Button>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  scrollContent: {
    paddingBottom: 30,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: 20,
    backgroundColor: 'white',
    borderBottomWidth: 1,
    borderBottomColor: '#e0e0e0',
  },
  backButton: {
    padding: 5,
  },
  title: {
    fontSize: 20,
    fontWeight: 'bold',
    color: '#333',
  },
  editButton: {
    padding: 5,
  },
  avatarSection: {
    alignItems: 'center',
    padding: 30,
    backgroundColor: 'white',
    marginBottom: 20,
  },
  avatar: {
    backgroundColor: '#4CAF50',
    marginBottom: 15,
  },
  username: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#333',
    marginBottom: 5,
  },
  email: {
    fontSize: 16,
    color: '#666',
  },
  statsContainer: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    paddingHorizontal: 10,
    marginBottom: 20,
  },
  statCard: {
    width: '48%',
    margin: '1%',
    elevation: 4,
  },
  statContent: {
    alignItems: 'center',
    padding: 15,
  },
  statNumber: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#333',
    marginTop: 10,
  },
  statLabel: {
    fontSize: 14,
    color: '#666',
    marginTop: 5,
    textAlign: 'center',
  },
  editCard: {
    margin: 20,
    marginBottom: 10,
    elevation: 4,
  },
  editTitle: {
    fontSize: 18,
    marginBottom: 20,
    color: '#333',
  },
  inputLabel: {
    fontSize: 16,
    fontWeight: '600',
    color: '#333',
    marginBottom: 8,
  },
  input: {
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 8,
    padding: 12,
    fontSize: 16,
    marginBottom: 20,
  },
  buttonRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  cancelButton: {
    flex: 1,
    marginRight: 10,
    borderColor: '#666',
  },
  saveButton: {
    flex: 1,
    marginLeft: 10,
    backgroundColor: '#4CAF50',
  },
  infoCard: {
    margin: 20,
    marginBottom: 10,
    elevation: 4,
  },
  infoTitle: {
    fontSize: 18,
    marginBottom: 20,
    color: '#333',
  },
  centered: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  infoRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    marginBottom: 15,
  },
  infoContent: {
    marginLeft: 15,
    flex: 1,
  },
  infoLabel: {
    fontSize: 14,
    color: '#666',
    textTransform: 'uppercase',
  },
  infoValue: {
    fontSize: 16,
    color: '#333',
    marginTop: 2,
  },
  logoutContainer: {
    padding: 20,
  },
  logoutButton: {
    borderColor: '#F44336',
  },
});

export default ProfileScreen;
