/* global importScripts, firebase */

// Fill this file from Firebase Console or regenerate with `flutterfire configure`
// before deploying browser push notifications.
const firebaseConfig = {
  apiKey: "AIzaSyBS8DaNBGAxi8yUd-y8xVgwtqIwpG4-qI8",
  authDomain: "omoienowa.firebaseapp.com",
  projectId: "omoienowa",
  storageBucket: "omoienowa.firebasestorage.app",
  messagingSenderId: "65944243975",
  appId: "1:65944243975:web:f2852f8731edbf9ff43fa2"
};

importScripts("https://www.gstatic.com/firebasejs/10.14.1/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.14.1/firebase-messaging-compat.js");

firebase.initializeApp(firebaseConfig);
firebase.messaging();
