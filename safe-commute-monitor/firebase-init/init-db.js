// Firebase Database Initialization Script - CommonJS Version
// Run this as: node init-db.js (install: npm i firebase-admin)

const admin = require('firebase-admin');
const crypto = require('crypto');

const serviceAccount = require('./serviceAccountKey.json'); // Download from Firebase Console > Project Settings > Service Accounts

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'safe-commute-cb13b',
});

const db = admin.firestore();

// Initialize sample data for Ghana InterCity Trans (COMPANY_001)
async function initializeDatabase() {
  console.log('Starting database initialization for Sep 14, 2025...');

  try {
    // 1. Single Company
    const companyRef = db.collection('companies').doc('COMPANY_001');
    await companyRef.set({
      name: 'Ghana InterCity Trans',
      companyId: 'COMPANY_001',
      contactEmail: 'admin@ghanatrans.com',
      phoneNumber: '+233302123456',
      address: 'Accra, Ghana',
      isActive: true,
      totalBuses: 50,
      totalDrivers: 100,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log('✅ Created company: Ghana InterCity Trans');

    // 2. Routes (Bidirectional, with codes A=Accra, K=Kumasi, etc.)
    const routes = [
      {
        id: 'A-K',
        name: 'Accra to Kumasi',
        origin: 'Accra (A)',
        destination: 'Kumasi (K)',
        distance: 250,
        estimatedDuration: '5 hours',
        fare: 120.00,
        description: 'Major intercity route',
        isActive: true,
        companyId: 'COMPANY_001',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {
        id: 'K-A',
        name: 'Kumasi to Accra',
        origin: 'Kumasi (K)',
        destination: 'Accra (A)',
        distance: 250,
        estimatedDuration: '5 hours',
        fare: 120.00,
        description: 'Major intercity route',
        isActive: true,
        companyId: 'COMPANY_001',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {
        id: 'A-T',
        name: 'Accra to Tamale',
        origin: 'Accra (A)',
        destination: 'Tamale (T)',
        distance: 600,
        estimatedDuration: '10 hours',
        fare: 200.00,
        description: 'Northern route',
        isActive: true,
        companyId: 'COMPANY_001',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {
        id: 'T-A',
        name: 'Tamale to Accra',
        origin: 'Tamale (T)',
        destination: 'Accra (A)',
        distance: 600,
        estimatedDuration: '10 hours',
        fare: 200.00,
        description: 'Northern route',
        isActive: true,
        companyId: 'COMPANY_001',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {
        id: 'K-S',
        name: 'Kumasi to Sunyani',
        origin: 'Kumasi (K)',
        destination: 'Sunyani (S)',
        distance: 120,
        estimatedDuration: '2.5 hours',
        fare: 50.00,
        description: 'Ashanti region',
        isActive: true,
        companyId: 'COMPANY_001',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {
        id: 'S-K',
        name: 'Sunyani to Kumasi',
        origin: 'Sunyani (S)',
        destination: 'Kumasi (K)',
        distance: 120,
        estimatedDuration: '2.5 hours',
        fare: 50.00,
        description: 'Ashanti region',
        isActive: true,
        companyId: 'COMPANY_001',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {
        id: 'A-H',
        name: 'Accra to Ho',
        origin: 'Accra (A)',
        destination: 'Ho (H)',
        distance: 180,
        estimatedDuration: '3 hours',
        fare: 80.00,
        description: 'Volta region',
        isActive: true,
        companyId: 'COMPANY_001',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {
        id: 'H-A',
        name: 'Ho to Accra',
        origin: 'Ho (H)',
        destination: 'Accra (A)',
        distance: 180,
        estimatedDuration: '3 hours',
        fare: 80.00,
        description: 'Volta region',
        isActive: true,
        companyId: 'COMPANY_001',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
    ];

    console.log('Creating routes...');
    for (const route of routes) {
      await db.collection('routes').doc(route.id).set(route);
      console.log(`✅ Created route: ${route.name}`);
    }

    // 3. Buses (Numbered A/T 001, etc.)
    const busPrefixes = ['A/T', 'T/A', 'A/K', 'K/A', 'K/S', 'S/K', 'A/H', 'H/A'];
    console.log('Creating buses...');
    for (let i = 0; i < 20; i++) {
      const prefix = busPrefixes[i % busPrefixes.length];
      const busNumber = `${prefix} ${String(Math.floor(i / busPrefixes.length) + 1).padStart(3, '0')}`;
      const busId = `BUS_${i + 1}`;
      await db.collection('buses').doc(busId).set({
        busNumber,
        capacity: 50,
        companyId: 'COMPANY_001',
        routeId: busPrefixes[i % busPrefixes.length],
        isActive: true,
        isAvailable: true,
        currentStatus: 'idle',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log(`✅ Created bus: ${busNumber} (ID: ${busId})`);
    }

    // 4. Sample Schedules (Sep 14, 2025 departures)
    const now = new Date('2025-09-14');
    const sampleSchedules = [
      { routeId: 'A-K', busId: 'BUS_1', departureTime: new Date(now.setHours(6, 0, 0)) },
      { routeId: 'A-K', busId: 'BUS_3', departureTime: new Date(now.setHours(10, 0, 0)) },
      { routeId: 'A-T', busId: 'BUS_2', departureTime: new Date(now.setHours(8, 0, 0)) },
      // Add more for testing
    ];
    console.log('Creating schedules...');
    for (const sched of sampleSchedules) {
      const busDoc = await db.collection('buses').doc(sched.busId).get();
      const busNumber = busDoc.data().busNumber;
      const routeDoc = await db.collection('routes').doc(sched.routeId).get();
      const routeName = routeDoc.data().name;
      await db.collection('schedules').add({
        routeId: sched.routeId,
        busId: sched.busId,
        busNumber,
        routeName,
        departureTime: admin.firestore.Timestamp.fromDate(sched.departureTime),
        status: 'scheduled',
        actualDeparture: null,
        actualArrival: null,
        companyId: 'COMPANY_001',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log(`✅ Created schedule: ${routeName} on ${sched.departureTime.toISOString()}`);
    }

    // 5. Sample Drivers (with hashed passwords)
    const sampleDrivers = [
      { email: 'driver1@ghanatrans.com', busNumber: 'A/T 001', name: 'John Doe' },
      { email: 'driver2@ghanatrans.com', busNumber: 'A/K 001', name: 'Jane Smith' },
    ];
    console.log('Creating drivers...');
    for (const driver of sampleDrivers) {
      const hashedPassword = crypto.createHash('sha256').update('password123').digest('hex'); // Default pw
      const driverId = `DRIVER_${driver.email.split('@')[0].toUpperCase()}`;
      await db.collection('drivers').doc(driverId).set({
        email: driver.email,
        passwordHash: hashedPassword,
        name: driver.name,
        busNumber: driver.busNumber,
        companyId: 'COMPANY_001',
        isActive: true,
        currentSession: null,
        currentRoute: null,
        currentAssignment: null,
        status: 'available',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        lastLogin: null,
      });
      console.log(`✅ Created driver: ${driver.name} (${driver.email})`);
    }

    // 6. Sample Tickets (Sep 14, 2025)
    const sampleTickets = [
      {
        ticketNumber: 'TKT-20250914-0001',
        passengerName: 'Test Passenger',
        phoneNumber: '+233123456789',
        routeId: 'A-K',
        routeName: 'Accra to Kumasi',
        busNumber: 'A/T 001',
        departureTime: admin.firestore.Timestamp.fromDate(new Date('2025-09-14T06:00:00Z')),
        fare: 120.00,
        isUsed: false,
        currentSession: null,
        origin: 'Accra (A)',
        destination: 'Kumasi (K)',
        companyId: 'COMPANY_001',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
    ];
    console.log('Creating sample tickets...');
    for (const ticket of sampleTickets) {
      await db.collection('tickets').add(ticket);
      console.log(`✅ Created ticket: ${ticket.ticketNumber}`);
    }

    // 7. Sample Complaints
    await db.collection('complaints').add({
      name: 'Test User',
      ticketNumber: 'TKT-20250914-0001',
      complaint: 'Delayed departure',
      status: 'pending',
      source: 'mobile',
      companyId: 'COMPANY_001',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log('✅ Created sample complaint');

    console.log('\n🎉 Database initialization completed successfully!');
    console.log('\n📊 Summary:');
    console.log('- 1 company (Ghana InterCity Trans)');
    console.log('- 8 routes (bidirectional Ghana intercity)');
    console.log('- 20 buses (numbered A/T 001, etc.)');
    console.log('- Sample schedules for Sep 14, 2025');
    console.log('- 2 drivers (email: driver1@ghanatrans.com, pw: password123)');
    console.log('- 1 sample ticket');
    console.log('- 1 sample complaint');
    
    console.log('\n🚌 Test Login:');
    console.log('- Driver: driver1@ghanatrans.com / password123');
    console.log('- Book ticket via app for routes like A-K');
    console.log('\n🔒 Security: Update rules in console for production');
  } catch (error) {
    console.error('❌ Error initializing database:', error);
    console.error('\nTroubleshooting:');
    console.error('1. Ensure serviceAccountKey.json is downloaded and valid');
    console.error('2. Check Firestore rules allow writes (test mode for dev)');
    console.error('3. Verify project ID: safe-commute-cb13b');
    console.error('4. Install: npm i firebase-admin');
  }
}

// Run initialization
initializeDatabase().then(() => {
  console.log('\n✅ Script completed. Test your app!');
  process.exit(0);
}).catch((error) => {
  console.error('❌ Script failed:', error);
  process.exit(1);
});