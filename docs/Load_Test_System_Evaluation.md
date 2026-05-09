# Load Test and System Evaluation

Course: COMP 490  
Project: SECURELY  
Group members: Ansh K Lal, Meera J Kasundra  
Date: [Date]

---

## 1. Describe Your System

SECURELY is a chat app our group built for class using Flutter. It runs on phones and computers. The app uses Google Firebase for the backend. People sign in with email and password or with Google. Messages and chat data are stored in Google Cloud Firestore, which is a database service from Firebase. The app can send push notifications. It also has extra login security (multi-factor authentication) and ways to protect data. Users can do voice and video calls inside the app.

**What users mainly do**

- Create an account or log in, and sometimes complete an extra security step after login.  
- See their chats or groups and open a conversation.  
- Read old messages and send new ones.  
- Make or join groups when the app allows it.  
- Start or answer voice or video calls.  
- Get notifications when something new happens, if they turned notifications on.

---

## 2. Design a Load Test

We would test with 50 users at the same time. Fifty is enough to see stress on the system without being so big that we cannot set it up for a class project.

**What each user does during the test**

1. Log in to the app (using test accounts, not real users).  
2. Open the screen that lists chats.  
3. Open one chat and load recent messages.  
4. Send a short test message.  
5. Wait about 20 seconds, then repeat opening a chat and sending a message.  
6. Keep doing that for the whole test run.

**How long the test runs**

We would run the load part for 8 minutes. Before that, we would start users gradually over 1 minute so they do not all hit login at the exact same second. So total time is about 9 minutes.

This is meant to copy real use: people logging in, reading chats, and sending messages over and over.

---

## 3. Define Success (Use Numbers)

We need clear numbers so we are not just saying the app should feel fast.

After login, the chat list should appear quickly.  
We would say the app passes if at least 95 out of 100 login tries result in the chat list showing up within 2 seconds after login succeeds.

Sending a message should not hang.  
At least 95 out of 100 sends should finish (the message is saved) within 1.5 seconds after the user taps send.

Opening a chat should load messages in a reasonable time.  
At least 95 out of 100 times, the first batch of messages should appear within 2.5 seconds.

Errors should stay low.  
Failed logins, failed sends, and timeouts should be less than one percent of all tries during the test.

The service should stay up.  
The app should be able to reach Firebase for at least 99 percent of the test window, meaning no long total outage.

---

## 4. Identify a Likely Bottleneck

We think the database is the most likely place things will slow down.

Most of what users do is read and write chat data in Firestore. When many people use the app together, the database has to handle a lot of reads and writes. If one chat or one document gets updated too often, or if the app asks for too much data at once, the database can get busy and responses can slow down.

The front end still has to draw the screen, but the part that usually hits limits first in this kind of app is storing and loading messages, not the drawing part. The network matters too, but a lot of the delay under load will still show up as waiting on the database.

So we pick database as the most likely bottleneck.

---

## 5. Suggest Improvements

**First idea: load messages in smaller chunks**  
Instead of loading every message in a long chat at once, load a page at a time (for example the newest 30 messages first, then older ones if the user scrolls up). That means less work per request and the screen can show something sooner.

**Second idea: stop listening when the user leaves a screen**  
If the app keeps listening for live updates on chats the user is not looking at, it keeps hitting the database. Turning those listeners off when the user navigates away would cut down extra reads and help performance when many users are active.

**Third idea: avoid updating the same document on every single message**  
If the app updates one shared summary document every time anyone sends a message, that one document becomes a hotspot. Spreading updates out or updating summary information less often would reduce pile-ups on one place in the database.

---

## Short Summary

SECURELY is a Firebase-backed chat app. Our load test uses 50 users for about 9 minutes doing login, reading chats, and sending messages. Good performance means specific time limits for most requests and less than one percent errors. We expect the database to be the weak point first. Loading data in pages, cleaning up listeners, and avoiding one document getting hammered would help.
