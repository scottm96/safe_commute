import { collection, addDoc, getDocs, doc, updateDoc, onSnapshot, query, orderBy, serverTimestamp, where, limit, Timestamp, getDoc } from 'firebase/firestore';
import { db } from '../firebase'; // Assume your firebase config file

export class FirebaseService {
  // Route-Bus Assignments (existing)
  static async assignBusToRoute(busId, routeId, scheduleData) {
    try {
      const assignmentRef = await addDoc(collection(db, 'bus_route_assignments'), {
        busId,
        routeId,
        driverId: scheduleData.driverId,
        busNumber: scheduleData.busNumber,
        routeName: scheduleData.routeName,
        scheduledDeparture: scheduleData.scheduledDeparture,
        scheduledArrival: scheduleData.scheduledArrival,
        isActive: true,
        status: 'scheduled',
        actualDeparture: null,
        actualArrival: null,
        passengerCount: 0,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp()
      });
      
      await updateDoc(doc(db, 'drivers', scheduleData.driverId), {
        currentRoute: routeId,
        currentAssignment: assignmentRef.id,
        status: 'assigned',
        updatedAt: serverTimestamp()
      });
      
      return { id: assignmentRef.id, busId, routeId, ...scheduleData };
    } catch (error) {
      console.error('Error assigning bus to route:', error);
      throw error;
    }
  }

  static async startTrip(assignmentId, driverId, startLocation) {
    try {
      const assignmentRef = doc(db, 'bus_route_assignments', assignmentId);
      await updateDoc(assignmentRef, {
        status: 'in_transit',
        actualDeparture: serverTimestamp(),
        departureLocation: startLocation,
        updatedAt: serverTimestamp()
      });

      const tripRef = await addDoc(collection(db, 'trip_tracking'), {
        assignmentId,
        driverId,
        startTime: serverTimestamp(),
        startLocation,
        endTime: null,
        endLocation: null,
        status: 'active',
        passengerPickups: [],
        incidents: [],
        totalDistance: 0,
        averageSpeed: 0
      });

      return tripRef.id;
    } catch (error) {
      console.error('Error starting trip:', error);
      throw error;
    }
  }

  static async endTrip(assignmentId, driverId, endLocation) {
    try {
      const assignmentRef = doc(db, 'bus_route_assignments', assignmentId);
      await updateDoc(assignmentRef, {
        status: 'completed',
        actualArrival: serverTimestamp(),
        arrivalLocation: endLocation,
        updatedAt: serverTimestamp()
      });

      const tripQuery = query(collection(db, 'trip_tracking'), where('assignmentId', '==', assignmentId));
      const tripSnap = await getDocs(tripQuery);
      if (!tripSnap.empty) {
        await updateDoc(doc(db, 'trip_tracking', tripSnap.docs[0].id), {
          endTime: serverTimestamp(),
          endLocation,
          status: 'completed'
        });
      }

      await updateDoc(doc(db, 'drivers', driverId), {
        currentAssignment: null,
        status: 'available',
        updatedAt: serverTimestamp()
      });

      return true;
    } catch (error) {
      console.error('Error ending trip:', error);
      throw error;
    }
  }

  // Bus Routes
  static async createBusRoute(routeData) {
    try {
      const docRef = await addDoc(collection(db, 'bus_routes'), {
        ...routeData,
        isActive: true,
        createdAt: serverTimestamp()
      });
      return { id: docRef.id, ...routeData };
    } catch (error) {
      console.error('Error creating bus route:', error);
      throw error;
    }
  }

  static async getBusRoutes() {
    try {
      const querySnapshot = await getDocs(collection(db, 'bus_routes'));
      return querySnapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      }));
    } catch (error) {
      console.error('Error getting bus routes:', error);
      throw error;
    }
  }

  static subscribeToRoutes(callback) {
    return onSnapshot(collection(db, 'bus_routes'), (snapshot) => {
      const routes = snapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      }));
      callback(routes);
    }, (error) => {
      console.error('Error in routes subscription:', error);
      callback([]);
    });
  }

  // Drivers Management
  static async createDriver(driverData) {
    try {
      const docRef = await addDoc(collection(db, 'drivers'), {
        ...driverData,
        isActive: true,
        currentSession: null,
        currentRoute: null,
        currentAssignment: null,
        status: 'available',
        createdAt: serverTimestamp(),
        lastLogin: null
      });
      return { id: docRef.id, ...driverData };
    } catch (error) {
      console.error('Error creating driver:', error);
      throw error;
    }
  }

  static async getDrivers() {
    try {
      const querySnapshot = await getDocs(collection(db, 'drivers'));
      return querySnapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      }));
    } catch (error) {
      console.error('Error getting drivers:', error);
      throw error;
    }
  }

  static async updateDriverStatus(driverId, statusData) {
    try {
      const driverRef = doc(db, 'driver_status', driverId);
      await updateDoc(driverRef, {
        ...statusData,
        lastUpdate: serverTimestamp()
      });
    } catch (error) {
      console.error('Error updating driver status:', error);
      throw error;
    }
  }

  // Companies
  static async getCompanies() {
    try {
      const querySnapshot = await getDocs(collection(db, 'companies'));
      return querySnapshot.docs.map(doc => ({
        id: doc.id,
        ...doc.data()
      }));
    } catch (error) {
      console.error('Error getting companies:', error);
      throw error;
    }
  }

  // New: Routes and Schedules
  static async getRoutes() {
    try {
      const q = query(collection(db, 'routes'), where('isActive', '==', true), where('companyId', '==', 'COMPANY_001'));
      const snapshot = await getDocs(q);
      return snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    } catch (error) {
      console.error('Error getting routes:', error);
      throw error;
    }
  }

  static async getSchedulesForRoute(routeId, date = new Date()) {
    const startOfDay = Timestamp.fromDate(new Date(date.getFullYear(), date.getMonth(), date.getDate(), 0, 0, 0));
    const endOfDay = Timestamp.fromDate(new Date(date.getFullYear(), date.getMonth(), date.getDate(), 23, 59, 59));
    try {
      const q = query(
        collection(db, 'schedules'),
        where('routeId', '==', routeId),
        where('departureTime', '>=', startOfDay),
        where('departureTime', '<=', endOfDay),
        where('status', '==', 'scheduled'),
        where('companyId', '==', 'COMPANY_001')
      );
      const snapshot = await getDocs(q);
      return snapshot.docs.map(doc => ({ id: doc.id, ...doc.data(), busNumber: doc.data().busNumber || 'TBA' }));
    } catch (error) {
      console.error('Error getting schedules:', error);
      throw error;
    }
  }

  static async getSchedules() {
    try {
      const q = query(collection(db, 'schedules'), where('companyId', '==', 'COMPANY_001'), orderBy('departureTime', 'desc'), limit(50));
      const snapshot = await getDocs(q);
      return snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    } catch (error) {
      console.error('Error getting schedules:', error);
      throw error;
    }
  }

  // Removed duplicate assignSchedule method. The enhanced version below will be used.

  static async logTripStart(scheduleId, driverId, startLocation) {
    try {
      await updateDoc(doc(db, 'schedules', scheduleId), {
        status: 'in_transit',
        actualDeparture: serverTimestamp(),
        departureLocation: startLocation
      });
      await updateDoc(doc(db, 'drivers', driverId), { 
        currentSchedule: scheduleId, 
        status: 'driving' 
      });
      return true;
    } catch (error) {
      console.error('Error logging trip start:', error);
      throw error;
    }
  }

  static async logTripEnd(scheduleId, driverId, endLocation) {
    try {
      await updateDoc(doc(db, 'schedules', scheduleId), {
        status: 'completed',
        actualArrival: serverTimestamp(),
        arrivalLocation: endLocation
      });
      await updateDoc(doc(db, 'drivers', driverId), { 
        currentSchedule: null, 
        status: 'available' 
      });
      const schedSnap = await getDoc(doc(db, 'schedules', scheduleId));
      const busId = schedSnap.data().busId;
      await updateDoc(doc(db, 'buses', busId), { isAvailable: true });
      return true;
    } catch (error) {
      console.error('Error logging trip end:', error);
      throw error;
    }
  }
  // Tickets and Complaints
  static async createTicket(ticketData) {
  try {
    const ticketWithExpiration = {
      ...ticketData,
      expiresAt: Timestamp.fromDate(new Date(Date.now() + 24 * 60 * 60 * 1000)), // 24 hours from now
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp()
    };
    
    const docRef = await addDoc(collection(db, 'tickets'), ticketWithExpiration);
    console.log('Ticket created with ID:', docRef.id);
    return { id: docRef.id, ...ticketWithExpiration };
  } catch (error) {
    console.error('Error creating ticket:', error);
    throw error;
  }
}


  static async getTickets() {
    try {
      const q = query(collection(db, 'tickets'), where('companyId', '==', 'COMPANY_001'), orderBy('createdAt', 'desc'), limit(50));
      const snapshot = await getDocs(q);
      return snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    } catch (error) {
      console.error('Error getting tickets:', error);
      throw error;
    }
  }

  // Complaints
  static async createComplaint(complaintData) {
    try {
      const docRef = await addDoc(collection(db, 'complaints'), {
        ...complaintData,
        createdAt: serverTimestamp()
      });
      return { id: docRef.id, ...complaintData };
    } catch (error) {
      console.error('Error creating complaint:', error);
      throw error;
    }
  }

  static subscribeToComplaints(callback) {
    const q = query(collection(db, 'complaints'), where('companyId', '==', 'COMPANY_001'), orderBy('createdAt', 'desc'));
    return onSnapshot(q, (snapshot) => {
      const complaints = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
      callback(complaints);
    });
  }

  // Enhanced Stats
  static async getComplaintStatistics() {
  try {
    console.log('Fetching complaint statistics...');
    
    const [totalSnap, pendingSnap, resolvedSnap] = await Promise.all([
      getDocs(query(
        collection(db, 'complaints'), 
        where('companyId', '==', 'COMPANY_001')
      )),
      getDocs(query(
        collection(db, 'complaints'), 
        where('status', '==', 'pending'), 
        where('companyId', '==', 'COMPANY_001')
      )),
      getDocs(query(
        collection(db, 'complaints'), 
        where('status', '==', 'resolved'), 
        where('companyId', '==', 'COMPANY_001')
      ))
    ]);

    const stats = {
      totalComplaints: totalSnap.size,
      pendingComplaints: pendingSnap.size,
      resolvedComplaints: resolvedSnap.size,
      mobileComplaints: Math.floor(totalSnap.size * 0.6),
      webComplaints: totalSnap.size - Math.floor(totalSnap.size * 0.6)
    };
    
    console.log('Complaint statistics:', stats);
    return stats;
  } catch (error) {
    console.error('Error getting complaint stats:', error);
    return {
      totalComplaints: 0,
      pendingComplaints: 0,
      resolvedComplaints: 0,
      mobileComplaints: 0,
      webComplaints: 0
    };
  }
}

  static async getTicketStatistics(period = 'monthly') {
  try {
    const now = new Date();
    let startDate;
    
    switch (period) {
      case 'daily': 
        startDate = new Date(now);
        startDate.setHours(0, 0, 0, 0);
        break;
      case 'weekly': 
        startDate = new Date(now - 7 * 86400000);
        break;
      case 'monthly': 
        startDate = new Date(now.getFullYear(), now.getMonth(), 1);
        break;
      case 'yearly': 
        startDate = new Date(now.getFullYear(), 0, 1);
        break;
      default: 
        startDate = new Date(now - 30 * 86400000);
    }

    console.log(`Fetching ${period} tickets from:`, startDate.toISOString());

    const q = query(
      collection(db, 'tickets'),
      where('createdAt', '>=', Timestamp.fromDate(startDate)),
      where('companyId', '==', 'COMPANY_001')
      // Removed isUsed filter - count all tickets, not just used ones
    );
    
    const snap = await getDocs(q);
    console.log(`Found ${snap.size} tickets for ${period} period`);
    
    if (snap.empty) {
      console.warn(`No tickets found for ${period} period`);
      return { tickets: [] };
    }

    const grouped = {};
    
    snap.forEach((doc) => {
      const data = doc.data();
      console.log('Processing ticket:', data);
      
      const dt = data.createdAt?.toDate() || new Date();
      let key;
      
      switch (period) {
        case 'daily':
          key = dt.toISOString().split('T')[0]; // YYYY-MM-DD
          break;
        case 'weekly': {
          const weekStart = new Date(dt);
          weekStart.setDate(dt.getDate() - dt.getDay()); // Start of week
          key = weekStart.toISOString().split('T')[0];
          break;
        }
        case 'monthly':
          key = dt.toISOString().slice(0, 7); // YYYY-MM
          break;
        case 'yearly':
          key = dt.getFullYear().toString();
          break;
        default:
          key = dt.toISOString().split('T')[0];
      }
      
      if (!grouped[key]) {
        grouped[key] = { 
          date: key, 
          count: 0, 
          revenue: 0 
        };
      }
      
      grouped[key].count += 1;
      // Use multiple possible field names for fare/price
      const ticketPrice = data.fare || data.price || data.amount || 0;
      grouped[key].revenue += ticketPrice;
    });

    const tickets = Object.values(grouped).sort((a, b) => a.date.localeCompare(b.date));
    console.log(`Grouped ${period} tickets:`, tickets);
    
    return { tickets };
  } catch (error) {
    console.error(`Error getting ${period} ticket stats:`, error);
    // Return empty structure instead of throwing
    return { tickets: [] };
  }
}

  static async getRevenueByPeriod(days = 30) {
  try {
    const endDate = new Date();
    const startDate = new Date(endDate.getTime() - days * 86400000);
    
    console.log(`Fetching revenue from ${startDate.toISOString()} to ${endDate.toISOString()}`);
    
    const q = query(
      collection(db, 'tickets'),
      where('createdAt', '>=', Timestamp.fromDate(startDate)),
      where('createdAt', '<=', Timestamp.fromDate(endDate)),
      where('companyId', '==', 'COMPANY_001')
      // Removed isUsed filter - count all ticket revenue
    );
    
    const snap = await getDocs(q);
    console.log(`Found ${snap.size} tickets for revenue calculation`);
    
    let totalRevenue = 0;
    snap.forEach((doc) => {
      const data = doc.data();
      const ticketPrice = data.fare || data.price || data.amount || 0;
      totalRevenue += ticketPrice;
    });
    
    const result = [{
      period: `Last ${days} days (${endDate.toLocaleDateString()})`,
      revenue: totalRevenue
    }];
    
    console.log('Revenue data:', result);
    return result;
  } catch (error) {
    console.error('Error getting revenue:', error);
    return [{ period: `Last ${days} days`, revenue: 0 }];
  }
}

  static async getBuses() {
    try {
      const q = query(collection(db, 'buses'), where('companyId', '==', 'COMPANY_001'), where('isActive', '==', true));
      const snapshot = await getDocs(q);
      return snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    } catch (error) {
      console.error('Error getting buses:', error);
      throw error;
    }
  }

  static subscribeToDrivers(callback) {
    const q = query(collection(db, 'driver_status'), where('companyId', '==', 'COMPANY_001'));
    return onSnapshot(q, (snapshot) => {
      const drivers = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
      callback(drivers);
    });
  }

  static subscribeToSchedules(routeId, callback) {
    const q = query(collection(db, 'schedules'), where('routeId', '==', routeId), where('companyId', '==', 'COMPANY_001'));
    return onSnapshot(q, (snapshot) => {
      const schedules = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
      callback(schedules);
    }, (error) => {
      console.error('Error in schedules subscription:', error);
      callback([]);
    });
  }

// Add these methods to your FirebaseService class to fix the issues

// 2. Add method to get all future schedules (for fallback)
static async getFutureSchedules() {
  try {
    const now = Timestamp.fromDate(new Date());
    const q = query(
      collection(db, 'schedules'),
      where('departureTime', '>=', now),
      where('companyId', '==', 'COMPANY_001'),
      orderBy('departureTime', 'asc'),
      limit(100)
    );
    const snapshot = await getDocs(q);
    return snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
  } catch (error) {
    console.error('Error getting future schedules:', error);
    throw error;
  }
}

// 3. Add method to make buses available again
static async makeBusAvailable(busId) {
  try {
    await updateDoc(doc(db, 'buses', busId), { 
      isAvailable: true,
      routeId: null, // Clear route assignment
      lastAssigned: serverTimestamp() 
    });
    return true;
  } catch (error) {
    console.error('Error making bus available:', error);
    throw error;
  }
}

// 4. Enhanced assignSchedule method with better error handling
static async assignSchedule(routeId, busId, departureTime) {
  try {
    // Check if bus exists and get bus data
    const busSnap = await getDoc(doc(db, 'buses', busId));
    if (!busSnap.exists()) throw new Error('Bus not found');
    const bus = busSnap.data();

    // Check if route exists and get route data
    const routeSnap = await getDoc(doc(db, 'routes', routeId));
    if (!routeSnap.exists()) throw new Error('Route not found');
    const route = routeSnap.data();

    // Check for conflicting schedules for this bus
    const conflictQuery = query(
      collection(db, 'schedules'),
      where('busId', '==', busId),
      where('status', 'in', ['scheduled', 'in_transit']),
      where('companyId', '==', 'COMPANY_001')
    );
    const conflictSnap = await getDocs(conflictQuery);
    
    // Check if there's a time conflict (within 2 hours)
    const departureTimestamp = Timestamp.fromDate(departureTime);
    const twoHoursBefore = Timestamp.fromDate(new Date(departureTime.getTime() - 2 * 60 * 60 * 1000));
    const twoHoursAfter = Timestamp.fromDate(new Date(departureTime.getTime() + 2 * 60 * 60 * 1000));
    
    const hasConflict = conflictSnap.docs.some(doc => {
      const existingDeparture = doc.data().departureTime;
      return existingDeparture >= twoHoursBefore && existingDeparture <= twoHoursAfter;
    });
    
    if (hasConflict) {
      throw new Error('Bus has a conflicting schedule within 2 hours of this time');
    }

    // Create the schedule
    const ref = await addDoc(collection(db, 'schedules'), {
      routeId,
      busId,
      busNumber: bus.busNumber || bus.plateNumber || `Bus-${busId.slice(-4)}`,
      routeName: route.name,
      departureTime: departureTimestamp,
      status: 'scheduled',
      actualDeparture: null,
      actualArrival: null,
      companyId: 'COMPANY_001',
      createdAt: serverTimestamp()
    });

    // Update bus assignment (but keep it available for other future schedules)
    await updateDoc(doc(db, 'buses', busId), { 
      routeId, 
      lastAssigned: serverTimestamp() 
      // Don't set isAvailable: false here, as bus can have multiple future schedules
    });

    return ref.id;
  } catch (error) {
    console.error('Error assigning schedule:', error);
    throw error;
  }
}

// 5. Add method to create test schedules for debugging
static async createTestSchedules(routeId, busId) {
  const testSchedules = [];
  const now = new Date();
  
  // Create 5 test schedules over the next 5 days
  for (let i = 1; i <= 5; i++) {
    const departureTime = new Date();
    departureTime.setDate(now.getDate() + i);
    departureTime.setHours(9 + (i * 2), 0, 0, 0); // 9 AM, 11 AM, 1 PM, etc.
    
    try {
      const scheduleId = await this.assignSchedule(routeId, busId, departureTime);
      testSchedules.push(scheduleId);
    } catch (error) {
      console.error(`Failed to create test schedule ${i}:`, error);
    }
  }
  
  console.log('Created test schedules:', testSchedules);
  return testSchedules;
}

static async createTestTickets() {
  console.log('Creating test tickets for debugging...');
  const testTickets = [];
  
  for (let i = 0; i < 10; i++) {
    const ticketDate = new Date();
    ticketDate.setDate(ticketDate.getDate() - i); // Spread over last 10 days
    
    const ticketData = {
      companyId: 'COMPANY_001',
      routeId: 'test-route',
      routeName: 'Accra - Kumasi',
      passengerName: `Test Passenger ${i + 1}`,
      passengerPhone: `020000000${i}`,
      fare: Math.floor(Math.random() * 50) + 20, // Random fare between 20-70
      seatNumber: `${Math.floor(Math.random() * 40) + 1}`,
      status: 'booked',
      isUsed: Math.random() > 0.3, // 70% chance of being used
      bookingDate: ticketDate,
      travelDate: new Date(ticketDate.getTime() + 86400000), // Next day
      createdAt: Timestamp.fromDate(ticketDate)
    };
    
    try {
      const docRef = await addDoc(collection(db, 'tickets'), ticketData);
      testTickets.push({ id: docRef.id, ...ticketData });
      console.log(`Created test ticket ${i + 1}:`, docRef.id);
    } catch (error) {
      console.error(`Failed to create test ticket ${i + 1}:`, error);
    }
  }
  
  console.log('Test tickets created:', testTickets.length);
  return testTickets;
}

static async debugTicketStructure() {
  try {
    console.log('=== DEBUGGING TICKET STRUCTURE ===');
    
    const q = query(
      collection(db, 'tickets'),
      where('companyId', '==', 'COMPANY_001'),
      limit(5)
    );
    
    const snap = await getDocs(q);
    console.log(`Found ${snap.size} tickets total`);
    
    if (snap.empty) {
      console.warn('No tickets found in database!');
      return;
    }
    
    snap.forEach((doc) => {
      const data = doc.data();
      console.log('Ticket structure:', {
        id: doc.id,
        createdAt: data.createdAt?.toDate(),
        fare: data.fare,
        price: data.price,
        amount: data.amount,
        isUsed: data.isUsed,
        companyId: data.companyId,
        status: data.status
      });
    });
    
    console.log('=== END DEBUG ===');
  } catch (error) {
    console.error('Error debugging ticket structure:', error);
  }
}

// Add this method to FirebaseService class
static async isTicketValid(ticketData) {
  if (ticketData.expiresAt) {
    const expirationTime = ticketData.expiresAt.toDate();
    const now = new Date();
    
    if (now > expirationTime) {
      return false; // Expired
    }
  }
  
  return true; // Valid
}

// Update createTicket method


}
