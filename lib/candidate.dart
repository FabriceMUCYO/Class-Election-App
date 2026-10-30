import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// MODEL: one candidate, as saved in Firestore.
class Candidate {
  Candidate({this.id = '', required this.name, this.votes = 0});

  final String id;
  final String name;
  final int votes;

  // Candidate -> Map (to save it).
  Map<String, dynamic> toMap() => {
    'name': name,
    'votes': votes,
  };

  // Firestore document -> Candidate (to show it).
  factory Candidate.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Candidate(
      id: doc.id,
      name: data['name'] as String,
      votes: (data['votes'] as num).toInt(),
    );
  }
}

// The signed-in user's document: users/{uid}
DocumentReference<Map<String, dynamic>> _myUser() {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  return FirebaseFirestore.instance.collection('users').doc(uid);
}

// users/{uid}/candidates
CollectionReference<Map<String, dynamic>> myCandidates() =>
    _myUser().collection('candidates');

// users/{uid}/voters  (the document id is the voter's cleaned name,
// so one voter can only have one document)
CollectionReference<Map<String, dynamic>> myVoters() =>
    _myUser().collection('voters');

// Sample data, written once when a new account is created.
Future<void> addSampleCandidates() async {
  final batch = FirebaseFirestore.instance.batch();
  for (final name in ['Keza', 'Mutoni', 'Gisa']) {
    batch.set(myCandidates().doc(), Candidate(name: name).toMap());
  }
  await batch.commit();
}