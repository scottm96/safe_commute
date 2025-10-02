import { initializeApp } from 'firebase/app';
import { getFirestore, } from 'firebase/firestore';
import { getAuth } from 'firebase/auth';

const firebaseConfig = {
  apiKey: 'AIzaSyCE1QgwebhQ8NL4lcloclFyVWyIzjWmvMY',
  appId: '1:521728664554:web:8ea0a5a61823fef9db4893',
  messagingSenderId: '521728664554',
  projectId: 'safe-commute-cb13b',
  authDomain: 'safe-commute-cb13b.firebaseapp.com',
  storageBucket: 'safe-commute-cb13b.firebasestorage.app',
};

// Initialize Firebase
const app = initializeApp(firebaseConfig);

// Initialize services
export const db = getFirestore(app);
export const auth = getAuth(app);

export default app;