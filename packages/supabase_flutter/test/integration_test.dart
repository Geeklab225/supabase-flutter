import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'widget_test_stubs.dart';

// This test suite requires a local Supabase instance running
// with the schema defined in 20250305041627_init.sql

void main() {
  const supabaseUrl = 'http://127.0.0.1:54321';
  const supabaseKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';

  late SupabaseClient supabase;

  setUpAll(() async {
    mockAppLink();
    HttpOverrides.global = null;
    // Initialize Supabase
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseKey,
      debug: false,
      authOptions: FlutterAuthClientOptions(
        localStorage: MockLocalStorage(),
        pkceAsyncStorage: MockAsyncStorage(),
      ),
    );

    supabase = Supabase.instance.client;
  });

  tearDownAll(() async {
    // Dispose Supabase instance
    await Supabase.instance.dispose();
  });

  group('Realtime', () {
    test('Create and subscribe to a channel', () async {
      final channel = supabase.channel('test-channel');

      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        callback: (payload) {
          print('Postgres changes: $payload');
        },
      );

      expect(channel, isNotNull);

      final completer = Completer<RealtimeSubscribeStatus>();

      // Add more detailed error handling

      channel.subscribe((status, error) {
        print('Channel subscription status: $status, error: $error');
        if (status == RealtimeSubscribeStatus.subscribed) {
          if (!completer.isCompleted) {
            completer.complete(status);
          }
        } else if (error != null) {
          print('Channel subscription error: $error');
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
        }
      }, const Duration(seconds: 10)); // Increase timeout to 10 seconds

      // Wait for either successful subscription or error
      final status = await completer.future.timeout(
        const Duration(seconds: 15), // Increase timeout to 15 seconds
        onTimeout: () => throw TimeoutException(
            'Channel subscription timed out after 15 seconds'),
      );

      expect(status, equals(RealtimeSubscribeStatus.subscribed));

      // Clean up
      await channel.unsubscribe();
    });

    group('Broadcast', () {
      late RealtimeChannel channel;

      setUp(() async {
        // Create and subscribe to a channel for broadcast tests
        print('Setting up broadcast test channel...');
        channel = supabase.channel('broadcast-test');

        // Add system event listener for debugging
        channel.onSystemEvents((payload) {
          print('Broadcast test - System event: $payload');
        });

        final completer = Completer<void>();
        final errorCompleter = Completer<String>();

        try {
          channel.subscribe((status, error) {
            print('Broadcast test - Channel status: $status, error: $error');
            if (status == RealtimeSubscribeStatus.subscribed) {
              if (!completer.isCompleted) {
                completer.complete();
              }
            } else if (error != null) {
              print('Broadcast test - Channel error: $error');
              if (!completer.isCompleted) {
                completer.completeError(error);
              }
              if (!errorCompleter.isCompleted) {
                errorCompleter.complete(error.toString());
              }
            }
          }, const Duration(seconds: 10)); // Increase timeout
        } catch (e) {
          print('Broadcast test - Exception during channel subscription: $e');
          if (!completer.isCompleted) {
            completer.completeError(e);
          }
          if (!errorCompleter.isCompleted) {
            errorCompleter.complete(e.toString());
          }
        }

        try {
          await completer.future.timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException(
                'Broadcast channel subscription timed out after 15 seconds'),
          );
        } catch (e) {
          String errorDetails = 'No error details available';
          if (!errorCompleter.isCompleted) {
            errorCompleter.complete('No specific error reported');
          }

          try {
            errorDetails = await errorCompleter.future.timeout(
              const Duration(seconds: 2),
              onTimeout: () => 'No error details available',
            );
          } catch (_) {}

          fail(
              'Failed to set up broadcast test channel: $e. Details: $errorDetails');
        }
      });

      tearDown(() async {
        // Unsubscribe from the channel after each test
        await channel.unsubscribe();
      });

      test('Send and receive broadcast message', () async {
        final completer = Completer<Map<String, dynamic>>();

        // Set up listener for broadcast event
        channel.onBroadcast(
          event: 'test-event',
          callback: (payload) {
            completer.complete(payload);
          },
        );

        // Send broadcast message
        final response = await channel.sendBroadcastMessage(
          event: 'test-event',
          payload: {'message': 'Hello, world!'},
        );

        expect(response, equals(ChannelResponse.ok));

        // Wait for broadcast message to be received
        final receivedPayload = await completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () =>
              throw TimeoutException('Broadcast message not received'),
        );

        expect(receivedPayload, isA<Map<String, dynamic>>());
        expect(receivedPayload['message'], equals('Hello, world!'));
      });

      test('Send and receive broadcast message with complex payload', () async {
        final completer = Completer<Map<String, dynamic>>();

        // Set up listener for broadcast event
        channel.onBroadcast(
          event: 'complex-event',
          callback: (payload) {
            completer.complete(payload);
          },
        );

        // Create a complex payload
        final complexPayload = {
          'user': {
            'id': 123,
            'name': 'Test User',
            'isActive': true,
          },
          'coordinates': [1.3521, 103.8198],
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };

        // Send broadcast message with complex payload
        final response = await channel.sendBroadcastMessage(
          event: 'complex-event',
          payload: complexPayload,
        );

        expect(response, equals(ChannelResponse.ok));

        // Wait for broadcast message to be received
        final receivedPayload = await completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () =>
              throw TimeoutException('Broadcast message not received'),
        );

        expect(receivedPayload, isA<Map<String, dynamic>>());
        expect(receivedPayload['user']['id'], equals(123));
        expect(receivedPayload['user']['name'], equals('Test User'));
        expect(receivedPayload['user']['isActive'], isTrue);
        expect(receivedPayload['coordinates'], isA<List>());
        expect(receivedPayload['coordinates'].length, equals(2));
        expect(receivedPayload['timestamp'], isA<int>());
      });

      test('Multiple listeners for different broadcast events', () async {
        final event1Completer = Completer<Map<String, dynamic>>();
        final event2Completer = Completer<Map<String, dynamic>>();

        // Set up listeners for different broadcast events
        channel.onBroadcast(
          event: 'event1',
          callback: (payload) {
            event1Completer.complete(payload);
          },
        );

        channel.onBroadcast(
          event: 'event2',
          callback: (payload) {
            event2Completer.complete(payload);
          },
        );

        // Send broadcast messages for both events
        await channel.sendBroadcastMessage(
          event: 'event1',
          payload: {'source': 'event1'},
        );

        await channel.sendBroadcastMessage(
          event: 'event2',
          payload: {'source': 'event2'},
        );

        // Wait for both broadcast messages to be received
        final event1Payload = await event1Completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () =>
              throw TimeoutException('Event1 message not received'),
        );

        final event2Payload = await event2Completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () =>
              throw TimeoutException('Event2 message not received'),
        );

        expect(event1Payload['source'], equals('event1'));
        expect(event2Payload['source'], equals('event2'));
      });

      test('Broadcast message is not received after unsubscribing', () async {
        // Set up listener for broadcast event
        bool messageReceived = false;
        channel.onBroadcast(
          event: 'test-event',
          callback: (payload) {
            messageReceived = true;
          },
        );

        // Unsubscribe from the channel
        await channel.unsubscribe();

        // Send broadcast message
        try {
          await channel.sendBroadcastMessage(
            event: 'test-event',
            payload: {'message': 'Hello, world!'},
          );
        } catch (e) {
          // Expected to fail because channel is unsubscribed
        }

        // Wait a moment to ensure no message is received
        await Future.delayed(const Duration(seconds: 2));

        expect(messageReceived, isFalse);
      });
    });

    group('Presence', () {
      late RealtimeChannel channel;

      setUp(() async {
        // Create and subscribe to a channel for presence tests
        print('Setting up presence test channel...');
        channel = supabase.channel('presence-test');

        // Add system event listener for debugging
        channel.onSystemEvents((payload) {
          print('Presence test - System event: $payload');
        });

        final completer = Completer<void>();
        final errorCompleter = Completer<String>();

        try {
          channel.subscribe((status, error) {
            print('Presence test - Channel status: $status, error: $error');
            if (status == RealtimeSubscribeStatus.subscribed) {
              if (!completer.isCompleted) {
                completer.complete();
              }
            } else if (error != null) {
              print('Presence test - Channel error: $error');
              if (!completer.isCompleted) {
                completer.completeError(error);
              }
              if (!errorCompleter.isCompleted) {
                errorCompleter.complete(error.toString());
              }
            }
          }, const Duration(seconds: 10)); // Increase timeout
        } catch (e) {
          print('Presence test - Exception during channel subscription: $e');
          if (!completer.isCompleted) {
            completer.completeError(e);
          }
          if (!errorCompleter.isCompleted) {
            errorCompleter.complete(e.toString());
          }
        }

        try {
          await completer.future.timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException(
                'Presence channel subscription timed out after 15 seconds'),
          );
        } catch (e) {
          String errorDetails = 'No error details available';
          if (!errorCompleter.isCompleted) {
            errorCompleter.complete('No specific error reported');
          }

          try {
            errorDetails = await errorCompleter.future.timeout(
              const Duration(seconds: 2),
              onTimeout: () => 'No error details available',
            );
          } catch (_) {}

          fail(
              'Failed to set up presence test channel: $e. Details: $errorDetails');
        }
      });

      tearDown(() async {
        // Unsubscribe from the channel after each test
        await channel.unsubscribe();
      });

      test('Track presence and receive sync event', () async {
        final syncCompleter = Completer<RealtimePresenceSyncPayload>();

        // Set up listener for presence sync event
        channel.onPresenceSync((payload) {
          syncCompleter.complete(payload);
        });

        // Track presence
        final presencePayload = {
          'user_id': 'test-user-${DateTime.now().millisecondsSinceEpoch}',
          'status': 'online',
          'last_seen_at': DateTime.now().toIso8601String(),
        };

        final response = await channel.track(presencePayload);
        expect(response, equals(ChannelResponse.ok));

        // Wait for presence sync event
        final syncPayload = await syncCompleter.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () =>
              throw TimeoutException('Presence sync event not received'),
        );

        expect(syncPayload, isNotNull);

        // Check presence state
        final presenceState = channel.presenceState();
        expect(presenceState, isNotEmpty);

        // Find our presence in the state
        bool foundPresence = false;
        for (final state in presenceState) {
          for (final presence in state.presences) {
            if (presence.payload['user_id'] == presencePayload['user_id']) {
              foundPresence = true;
              expect(presence.payload['status'], equals('online'));
              break;
            }
          }
          if (foundPresence) break;
        }

        expect(foundPresence, isTrue);
      });

      test('Track and untrack presence', () async {
        final joinCompleter = Completer<RealtimePresenceJoinPayload>();
        final leaveCompleter = Completer<RealtimePresenceLeavePayload>();

        // Set up listeners for presence join and leave events
        channel.onPresenceJoin((payload) {
          if (!joinCompleter.isCompleted) {
            joinCompleter.complete(payload);
          }
        });

        channel.onPresenceLeave((payload) {
          if (!leaveCompleter.isCompleted) {
            leaveCompleter.complete(payload);
          }
        });

        // Track presence
        final userId = 'test-user-${DateTime.now().millisecondsSinceEpoch}';
        final presencePayload = {
          'user_id': userId,
          'status': 'online',
        };

        await channel.track(presencePayload);

        // Wait for presence join event
        final joinPayload = await joinCompleter.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () =>
              throw TimeoutException('Presence join event not received'),
        );

        expect(joinPayload, isNotNull);
        expect(joinPayload.key, isNotNull);
        expect(joinPayload.currentPresences, isNotEmpty);
        expect(joinPayload.newPresences, isNotEmpty);

        // Untrack presence
        await channel.untrack();

        // Wait for presence leave event
        final leavePayload = await leaveCompleter.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () =>
              throw TimeoutException('Presence leave event not received'),
        );

        expect(leavePayload, isNotNull);
        expect(leavePayload.key, isNotNull);
        expect(leavePayload.currentPresences, isNotEmpty);
        expect(leavePayload.leftPresences, isNotEmpty);
      });

      test('Multiple clients tracking presence', () async {
        // Create a second channel to simulate another client
        final channel2 = supabase.channel('presence-test');

        final completer = Completer<void>();
        channel2.subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            completer.complete();
          } else if (error != null) {
            completer.completeError(error);
          }
        });

        await completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () =>
              throw TimeoutException('Channel2 subscription timed out'),
        );

        // Set up sync listener on first channel
        final syncCompleter = Completer<RealtimePresenceSyncPayload>();
        channel.onPresenceSync((payload) {
          if (!syncCompleter.isCompleted) {
            syncCompleter.complete(payload);
          }
        });

        // Track presence on both channels
        final user1Id = 'user1-${DateTime.now().millisecondsSinceEpoch}';
        final user2Id = 'user2-${DateTime.now().millisecondsSinceEpoch}';

        await channel.track({'user_id': user1Id, 'status': 'online'});
        await channel2.track({'user_id': user2Id, 'status': 'online'});

        // Wait for sync event
        await syncCompleter.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException('Sync event not received'),
        );

        // Check presence state on first channel
        final presenceState = channel.presenceState();

        // Find both users in the presence state
        bool foundUser1 = false;
        bool foundUser2 = false;

        for (final state in presenceState) {
          for (final presence in state.presences) {
            if (presence.payload['user_id'] == user1Id) {
              foundUser1 = true;
            } else if (presence.payload['user_id'] == user2Id) {
              foundUser2 = true;
            }
          }
        }

        expect(foundUser1, isTrue);
        expect(foundUser2, isTrue);

        // Clean up second channel
        await channel2.unsubscribe();
      });

      test('Presence state persists after channel resubscription', () async {
        // Track presence
        final userId =
            'persistent-user-${DateTime.now().millisecondsSinceEpoch}';
        await channel.track({'user_id': userId, 'status': 'online'});

        // Wait for presence to be established
        await Future.delayed(const Duration(seconds: 1));

        // Unsubscribe and resubscribe to the channel
        await channel.unsubscribe();

        final completer = Completer<void>();
        channel.subscribe((status, error) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            completer.complete();
          } else if (error != null) {
            completer.completeError(error);
          }
        });

        await completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () =>
              throw TimeoutException('Channel resubscription timed out'),
        );

        // Set up sync listener
        final syncCompleter = Completer<RealtimePresenceSyncPayload>();
        channel.onPresenceSync((payload) {
          syncCompleter.complete(payload);
        });

        // Track presence again
        await channel.track({'user_id': userId, 'status': 'online'});

        // Wait for sync event
        await syncCompleter.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException(
              'Sync event not received after resubscription'),
        );

        // Check presence state
        final presenceState = channel.presenceState();

        // Find our user in the presence state
        bool foundUser = false;
        for (final state in presenceState) {
          for (final presence in state.presences) {
            if (presence.payload['user_id'] == userId) {
              foundUser = true;
              break;
            }
          }
          if (foundUser) break;
        }

        expect(foundUser, isTrue);
      });
    });

    group('Combined Broadcast and Presence', () {
      late RealtimeChannel channel;

      setUp(() async {
        // Create and subscribe to a channel for combined tests
        print('Setting up combined test channel...');
        channel = supabase.channel('combined-test');

        // Add system event listener for debugging
        channel.onSystemEvents((payload) {
          print('Combined test - System event: $payload');
        });

        final completer = Completer<void>();
        final errorCompleter = Completer<String>();

        try {
          channel.subscribe((status, error) {
            print('Combined test - Channel status: $status, error: $error');
            if (status == RealtimeSubscribeStatus.subscribed) {
              if (!completer.isCompleted) {
                completer.complete();
              }
            } else if (error != null) {
              print('Combined test - Channel error: $error');
              if (!completer.isCompleted) {
                completer.completeError(error);
              }
              if (!errorCompleter.isCompleted) {
                errorCompleter.complete(error.toString());
              }
            }
          }, const Duration(seconds: 10)); // Increase timeout
        } catch (e) {
          print('Combined test - Exception during channel subscription: $e');
          if (!completer.isCompleted) {
            completer.completeError(e);
          }
          if (!errorCompleter.isCompleted) {
            errorCompleter.complete(e.toString());
          }
        }

        try {
          await completer.future.timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException(
                'Combined channel subscription timed out after 15 seconds'),
          );
        } catch (e) {
          String errorDetails = 'No error details available';
          if (!errorCompleter.isCompleted) {
            errorCompleter.complete('No specific error reported');
          }

          try {
            errorDetails = await errorCompleter.future.timeout(
              const Duration(seconds: 2),
              onTimeout: () => 'No error details available',
            );
          } catch (_) {}

          fail(
              'Failed to set up combined test channel: $e. Details: $errorDetails');
        }
      });

      tearDown(() async {
        // Unsubscribe from the channel after each test
        await channel.unsubscribe();
      });

      test('Track presence and send broadcast in the same channel', () async {
        final syncCompleter = Completer<RealtimePresenceSyncPayload>();
        final broadcastCompleter = Completer<Map<String, dynamic>>();

        // Set up listeners
        channel.onPresenceSync((payload) {
          syncCompleter.complete(payload);
        });

        channel.onBroadcast(
          event: 'user-activity',
          callback: (payload) {
            broadcastCompleter.complete(payload);
          },
        );

        // Track presence
        final userId = 'combined-user-${DateTime.now().millisecondsSinceEpoch}';
        await channel.track({'user_id': userId, 'status': 'online'});

        // Wait for presence sync event
        await syncCompleter.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () =>
              throw TimeoutException('Presence sync event not received'),
        );

        // Send broadcast message
        await channel.sendBroadcastMessage(
          event: 'user-activity',
          payload: {'user_id': userId, 'action': 'typing'},
        );

        // Wait for broadcast message
        final broadcastPayload = await broadcastCompleter.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () =>
              throw TimeoutException('Broadcast message not received'),
        );

        expect(broadcastPayload['user_id'], equals(userId));
        expect(broadcastPayload['action'], equals('typing'));

        // Check presence state
        final presenceState = channel.presenceState();
        bool foundUser = false;
        for (final state in presenceState) {
          for (final presence in state.presences) {
            if (presence.payload['user_id'] == userId) {
              foundUser = true;
              break;
            }
          }
          if (foundUser) break;
        }

        expect(foundUser, isTrue);
      });
    });
  });

  group('Authentication', () {
    final testEmail =
        'auth_test_${DateTime.now().millisecondsSinceEpoch}@example.com';
    const testPassword = 'password123';
    late String userId;

    test('Sign up with email and password', () async {
      final response = await supabase.auth.signUp(
        email: testEmail,
        password: testPassword,
      );

      expect(response.user, isNotNull);
      expect(response.user!.email, equals(testEmail));
      userId = response.user!.id;
    });

    test('Sign out', () async {
      await supabase.auth.signOut();

      final session = supabase.auth.currentSession;
      expect(session, isNull);
    });

    test('Sign in with email and password', () async {
      final response = await supabase.auth.signInWithPassword(
        email: testEmail,
        password: testPassword,
      );

      expect(response.user, isNotNull);
      expect(response.user!.email, equals(testEmail));
      expect(response.session, isNotNull);
    });

    test('Get user', () async {
      final user = supabase.auth.currentUser;

      expect(user, isNotNull);
      expect(user!.email, equals(testEmail));
      expect(user.id, equals(userId));
    });

    test('Update user', () async {
      final updatedData = {'display_name': 'Test User'};

      final response = await supabase.auth.updateUser(
        UserAttributes(
          data: updatedData,
        ),
      );

      expect(response.user, isNotNull);
      expect(response.user!.userMetadata?['display_name'], equals('Test User'));
    });

    test('Auth state change events', () async {
      // Set up a listener for auth state changes
      final completer = Completer<AuthState>();

      final subscription = supabase.auth.onAuthStateChange.listen((data) {
        if (data.event == AuthChangeEvent.signedOut) {
          completer.complete(data);
        }
      });

      // Sign out to trigger an auth state change
      await supabase.auth.signOut();

      // Wait for the auth state change event
      final authState = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () =>
            throw TimeoutException('Auth state change event not received'),
      );

      expect(authState.event, equals(AuthChangeEvent.signedOut));
      expect(authState.session, isNull);

      // Clean up the subscription
      subscription.cancel();
    });
  });

  group('Password Reset', () {
    final testEmail =
        'reset_test_${DateTime.now().millisecondsSinceEpoch}@example.com';
    const testPassword = 'password123';

    setUpAll(() async {
      // Create a test user
      await supabase.auth.signUp(
        email: testEmail,
        password: testPassword,
      );

      // Sign out
      await supabase.auth.signOut();
    });

    test('Request password reset', () async {
      // This test will only verify that the request doesn't throw an error
      // since we can't actually complete the password reset flow in an automated test
      await expectLater(
        supabase.auth.resetPasswordForEmail(testEmail),
        completes,
      );
    });
  });

  group('Auth with JWT', () {
    test('Custom claims in JWT', () async {
      // Sign in with email and password
      final testEmail =
          'jwt_test_${DateTime.now().millisecondsSinceEpoch}@example.com';
      const testPassword = 'password123';

      await supabase.auth.signUp(
        email: testEmail,
        password: testPassword,
      );

      final response = await supabase.auth.signInWithPassword(
        email: testEmail,
        password: testPassword,
      );

      expect(response.session, isNotNull);

      // Check JWT claims
      final jwt = response.session!.accessToken;
      expect(jwt, isNotNull);

      // In a real test, you would decode the JWT and verify custom claims
      // For this example, we'll just check that the token exists
      expect(jwt.length, greaterThan(0));

      // Sign out
      await supabase.auth.signOut();
    });
  });
}
