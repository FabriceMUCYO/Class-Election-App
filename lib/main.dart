import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'auth_gate.dart';
import 'candidate.dart';
import 'firebase_options.dart';
import 'weather.dart';

// The main color of the app (teal green).
const Color brandColor = Color(0xFF0F766E);
const Color borderColor = Color(0xFFD3E2DF);
const Color darkTextColor = Color(0xFF12332F);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // If Firebase cannot start, show a clear message instead of a blank screen.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    runApp(StartupErrorApp(error: e.toString()));
    return;
  }

  runApp(const ClassElectionApp());
}

// Shown only when Firebase fails to start (for example on Chrome or Windows
// without firebase_options.dart).
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 60, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Firebase could not start',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Run the app on an Android emulator or phone. '
                  'To run it on Chrome you must run "flutterfire configure" first.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ClassElectionApp extends StatelessWidget {
  const ClassElectionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Class Election',

      // TEAL GREEN THEME, FLAT CARDS
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF3F7F6),
        colorScheme: ColorScheme.fromSeed(
          seedColor: brandColor,
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: brandColor,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: borderColor),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: brandColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),

      // The gate decides: login screen or the election.
      home: const AuthGate(),
    );
  }
}

// Small dialog used to edit a candidate's name.
// It is its own widget so that it can dispose its controller safely.
class EditNameDialog extends StatefulWidget {
  const EditNameDialog({super.key, required this.initialName});

  final String initialName;

  @override
  State<EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends State<EditNameDialog> {
  late final TextEditingController controller =
      TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit candidate'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Candidate name'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class ElectionHome extends StatefulWidget {
  const ElectionHome({super.key});

  @override
  State<ElectionHome> createState() => _ElectionHomeState();
}

class _ElectionHomeState extends State<ElectionHome> {
  final voterController = TextEditingController();
  final candidateController = TextEditingController();

  // The candidates live in Firestore. The screen listens to them.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> candidatesStream =
      myCandidates().orderBy('name').snapshots();

  // WEATHER (live data from the API): three states.
  Weather? weather;
  bool weatherLoading = true;
  String? weatherError;

  @override
  void initState() {
    super.initState();
    loadWeather();
  }

  @override
  void dispose() {
    voterController.dispose();
    candidateController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // LOGIC
  // ---------------------------------------------------------------------

  // LOAD THE WEATHER FROM THE SERVER.
  Future<void> loadWeather() async {
    setState(() {
      weatherLoading = true;
      weatherError = null;
    });

    try {
      final result = await fetchWeather();
      if (!mounted) return;
      setState(() {
        weather = result;
        weatherLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        weatherLoading = false;
        weatherError = 'Could not load the weather. Check your internet.';
      });
    }
  }

  // COMPUTED, NEVER SAVED: total votes.
  int totalVotesOf(List<Candidate> candidates) {
    return candidates.fold<int>(0, (sum, c) => sum + c.votes);
  }

  // CLEAN AND FORMAT NAMES.
  String cleanName(String input) {
    final trimmed = input.trim();

    if (trimmed.isEmpty) {
      return '';
    }

    final words = trimmed.split(RegExp(r'\s+'));

    return words.map((word) {
      final lower = word.toLowerCase();
      return lower[0].toUpperCase() + lower.substring(1);
    }).join(' ');
  }

  // The voter's document id. A "/" is not allowed in a document id.
  String voterKey(String name) =>
      cleanName(name).toLowerCase().replaceAll('/', '-');

  // SHOW A MESSAGE.
  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // RECORD A VOTE.
  Future<void> castVote(Candidate candidate) async {
    final voter = cleanName(voterController.text);

    if (voter.isEmpty) {
      showMessage('Please enter your name first.');
      return;
    }

    try {
      final voterDoc = myVoters().doc(voterKey(voter));

      // Has this voter already voted?
      final existing = await voterDoc.get();
      if (!mounted) return;
      if (existing.exists) {
        showMessage('$voter has already voted.');
        return;
      }

      // One batch: remember the voter AND add 1 to the candidate.
      // Both happen, or none.
      final batch = FirebaseFirestore.instance.batch();
      batch.set(voterDoc, {
        'name': voter,
        'candidate': candidate.name,
        'candidateId': candidate.id,
      });
      batch.update(
        myCandidates().doc(candidate.id),
        {'votes': FieldValue.increment(1)},
      );
      await batch.commit();

      if (!mounted) return;
      voterController.clear();
      showVoteSuccess(candidate.name);
    } catch (e) {
      if (!mounted) return;
      showMessage('Could not save your vote. Check your connection.');
    }
  }

  // ADD A CANDIDATE.
  Future<void> addCandidate() async {
    final name = cleanName(candidateController.text);

    if (name.isEmpty) {
      showMessage('Candidate name cannot be empty.');
      return;
    }

    try {
      final duplicate = await myCandidates()
          .where('name', isEqualTo: name)
          .limit(1)
          .get();
      if (!mounted) return;

      if (duplicate.docs.isNotEmpty) {
        showMessage('$name already exists.');
        return;
      }

      await myCandidates().add(Candidate(name: name).toMap());
      if (!mounted) return;
      candidateController.clear();
      showMessage('$name was added.');
    } catch (e) {
      if (!mounted) return;
      showMessage('Could not add the candidate. Check your connection.');
    }
  }

  // EDIT A CANDIDATE'S NAME (Firestore update).
  Future<void> editCandidate(Candidate candidate) async {
    final typed = await showDialog<String>(
      context: context,
      builder: (dialogContext) => EditNameDialog(initialName: candidate.name),
    );

    if (typed == null || !mounted) return;

    final newName = cleanName(typed);

    if (newName.isEmpty) {
      showMessage('Candidate name cannot be empty.');
      return;
    }

    if (newName == candidate.name) {
      return;
    }

    try {
      final duplicate = await myCandidates()
          .where('name', isEqualTo: newName)
          .limit(1)
          .get();
      if (!mounted) return;

      if (duplicate.docs.isNotEmpty) {
        showMessage('$newName already exists.');
        return;
      }

      await myCandidates().doc(candidate.id).update({'name': newName});
      if (!mounted) return;
      showMessage('Candidate renamed to $newName.');
    } catch (e) {
      if (!mounted) return;
      showMessage('Could not edit the candidate.');
    }
  }

  // REMOVE A CANDIDATE WITH ZERO VOTES.
  Future<void> removeCandidate(Candidate candidate) async {
    if (candidate.votes > 0) {
      showMessage('You cannot remove a candidate who has votes.');
      return;
    }

    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this candidate?'),
        content: Text(candidate.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (sure != true || !mounted) return;

    try {
      await myCandidates().doc(candidate.id).delete();
      if (!mounted) return;
      showMessage('${candidate.name} was removed.');
    } catch (e) {
      if (!mounted) return;
      showMessage('Could not remove the candidate.');
    }
  }

  // RESET THE ELECTION.
  Future<void> confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset election?'),
        content: const Text('This will clear all votes. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final voters = await myVoters().get();
      final candidates = await myCandidates().get();

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in voters.docs) {
        batch.delete(doc.reference);
      }
      for (final doc in candidates.docs) {
        batch.update(doc.reference, {'votes': 0});
      }
      await batch.commit();

      if (!mounted) return;
      showMessage('Election has been reset.');
    } catch (e) {
      if (!mounted) return;
      showMessage('Could not reset the election.');
    }
  }

  // SELECTION SORT: HIGHEST VOTES FIRST.
  List<Candidate> rankedCandidates(List<Candidate> candidates) {
    final remaining = List<Candidate>.of(candidates);
    final ranked = <Candidate>[];

    while (remaining.isNotEmpty) {
      int bestIndex = 0;

      for (int i = 1; i < remaining.length; i++) {
        if (remaining[i].votes > remaining[bestIndex].votes) {
          bestIndex = i;
        }
      }

      ranked.add(remaining.removeAt(bestIndex));
    }

    return ranked;
  }

  // DETERMINE THE ELECTION RESULT.
  String electionResult(List<Candidate> candidates) {
    if (candidates.isEmpty) {
      return 'No candidates available';
    }

    if (totalVotesOf(candidates) == 0) {
      return 'No votes yet';
    }

    final highestVotes = candidates
        .map((candidate) => candidate.votes)
        .reduce((a, b) => a > b ? a : b);

    final leaders = candidates
        .where((candidate) => candidate.votes == highestVotes)
        .toList();

    if (leaders.length > 1) {
      final names = leaders.map((candidate) => candidate.name).join(' and ');
      return 'Tie between $names ($highestVotes votes each)';
    }

    return 'Winner: ${leaders.first.name}';
  }

  // The three-dot menu in the top bar.
  void onMenuSelected(String value) {
    if (value == 'reset') {
      confirmReset();
    } else if (value == 'logout') {
      FirebaseAuth.instance.signOut();
    }
  }

  // ---------------------------------------------------------------------
  // SCREEN FRAME: top bar + tabs + weather strip
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Class Election',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            PopupMenuButton<String>(
              onSelected: onMenuSelected,
              itemBuilder: (context) => const [
                PopupMenuItem<String>(
                  value: 'reset',
                  child: Text('Reset election'),
                ),
                PopupMenuItem<String>(
                  value: 'logout',
                  child: Text('Log out'),
                ),
              ],
            ),
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(icon: Icon(Icons.how_to_vote_outlined), text: 'Vote'),
              Tab(icon: Icon(Icons.groups_outlined), text: 'Candidates'),
              Tab(icon: Icon(Icons.bar_chart), text: 'Results'),
            ],
          ),
        ),
        body: Column(
          children: [
            buildWeatherStrip(),
            Expanded(child: buildTabs()),
          ],
        ),
      ),
    );
  }

  // WEATHER STRIP under the top bar: loading, error, or data.
  Widget buildWeatherStrip() {
    final scheme = Theme.of(context).colorScheme;

    Widget message;

    if (weatherLoading) {
      message = const Text('Loading the weather...');
    } else if (weatherError != null) {
      message = Row(
        children: [
          Expanded(child: Text(weatherError!)),
          TextButton(
            onPressed: loadWeather,
            child: const Text('Retry'),
          ),
        ],
      );
    } else {
      message = Text(
        'Election day weather in Kigali: '
        '${weather!.temperature.round()}°C · ${describe(weather!.code)}',
      );
    }

    return Container(
      width: double.infinity,
      color: scheme.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
        child: Row(
          children: [
            Icon(
              Icons.wb_sunny_outlined,
              size: 20,
              color: scheme.onPrimaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(child: message),
          ],
        ),
      ),
    );
  }

  // The three tabs. The list comes from Firestore: loading, error, then data.
  Widget buildTabs() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: candidatesStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load the election.\n${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final candidates = snapshot.data!.docs.map(Candidate.fromDoc).toList();

        return TabBarView(
          children: [
            buildVoteTab(candidates),
            buildCandidatesTab(candidates),
            buildResultsTab(candidates),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------
  // TAB 1: VOTE
  // ---------------------------------------------------------------------

  Widget buildVoteTab(List<Candidate> candidates) {
    final totalVotes = totalVotesOf(candidates);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Choose your class representative',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: darkTextColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Votes recorded: $totalVotes',
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: voterController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Your full name',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 16),

        // EMPTY STATE
        if (candidates.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: Text('No candidates yet. Add one in the Candidates tab.'),
            ),
          ),

        ...candidates.map(
          (candidate) => Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 6,
              ),
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                foregroundColor:
                    Theme.of(context).colorScheme.onPrimaryContainer,
                child: Text(
                  candidate.name.isEmpty ? '?' : candidate.name[0],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              title: Text(
                candidate.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text('${candidate.votes} votes'),
              trailing: FilledButton(
                onPressed: () => castVote(candidate),
                child: const Text('Vote'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // TAB 2: CANDIDATES (add, edit, remove)
  // ---------------------------------------------------------------------

  Widget buildCandidatesTab(List<Candidate> candidates) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Manage candidates',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: darkTextColor,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: candidateController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'New candidate name',
            prefixIcon: Icon(Icons.person_add_outlined),
          ),
          onSubmitted: (_) => addCandidate(),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: addCandidate,
            icon: const Icon(Icons.person_add),
            label: const Text('Add candidate'),
          ),
        ),
        const SizedBox(height: 16),
        if (candidates.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: Text('No candidates yet.')),
          ),
        ...candidates.map(
          (candidate) => Card(
            child: ListTile(
              title: Text(candidate.name),
              subtitle: Text('${candidate.votes} votes'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Edit candidate',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => editCandidate(candidate),
                  ),
                  IconButton(
                    tooltip: 'Remove candidate',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => removeCandidate(candidate),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // TAB 3: RESULTS
  // ---------------------------------------------------------------------

  Widget buildResultsTab(List<Candidate> candidates) {
    final ranked = rankedCandidates(candidates);
    final totalVotes = totalVotesOf(candidates);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Winner banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: brandColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              const Icon(Icons.emoji_events, size: 44, color: Colors.white),
              const SizedBox(height: 10),
              Text(
                electionResult(candidates),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Total votes: $totalVotes',
                style: const TextStyle(fontSize: 15, color: Colors.white70),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        const Text(
          'Candidate Rankings',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: darkTextColor,
          ),
        ),

        const SizedBox(height: 10),

        if (totalVotes == 0)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: Text(
                  'No votes yet. Percentages will appear after voting.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),

        ...List.generate(ranked.length, (index) {
          final candidate = ranked[index];

          final fraction = totalVotes == 0 ? 0.0 : candidate.votes / totalVotes;
          final percentage = fraction * 100;

          final medal = switch (index) {
            0 => '🥇',
            1 => '🥈',
            2 => '🥉',
            _ => '${index + 1}.',
          };

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(medal, style: const TextStyle(fontSize: 23)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          candidate.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: darkTextColor,
                          ),
                        ),
                      ),
                      Text(
                        '${candidate.votes} votes',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: brandColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 10,
                      backgroundColor: const Color(0xFFD9ECE9),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        brandColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${percentage.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // VOTE-SUCCESS SCREEN
  // ---------------------------------------------------------------------

  void showVoteSuccess(String candidateName) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: brandColor,
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'You voted!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle_outline,
                        color: Colors.white,
                        size: 76,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Your vote for $candidateName was recorded.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 17),
                    ),
                    const SizedBox(height: 32),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Back to candidates'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
