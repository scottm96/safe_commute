import React, { useEffect, useState, useRef } from "react";
import { FileText, User, Phone, Calendar, AlertCircle, CheckCircle, Smartphone, Monitor, Bus, MapPin, Clock, Printer } from "lucide-react";
import { useReactToPrint } from "react-to-print";
import { QRCodeCanvas as QRCode } from "qrcode.react";
import { FirebaseService } from "../services/firebaseService";

function generateTicketNumber(existingTickets) {
  const now = new Date();
  const date = now.toISOString().split("T")[0].replace(/-/g, "");
  const todayCount = existingTickets.filter(t => t.ticketNumber && t.ticketNumber.includes(`TKT-${date}-`)).length;
  const next = todayCount + 1;
  return `TKT-${date}-${String(next).padStart(4, "0")}`;
}

export function TicketPage() {
  const [routes, setRoutes] = useState([]);
  const [schedules, setSchedules] = useState([]);
  const [allSchedules, setAllSchedules] = useState([]);
  const [selectedRoute, setSelectedRoute] = useState('');
  const [selectedSchedule, setSelectedSchedule] = useState(null);
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [tickets, setTickets] = useState([]);
  const [loading, setLoading] = useState(true);
  const [showTicketPreview, setShowTicketPreview] = useState(false);
  const [bookedTicket, setBookedTicket] = useState(null);
  
  const componentRef = useRef();

  const handlePrint = useReactToPrint({
    contentRef: componentRef,
  });

  useEffect(() => {
    loadData();
  }, []);

  const loadData = async () => {
    try {
      const [routeData, ticketData, scheduleData] = await Promise.all([
        FirebaseService.getRoutes(),
        FirebaseService.getTickets(),
        FirebaseService.getSchedules()
      ]);
      
      setRoutes(routeData);
      setTickets(ticketData);
      setAllSchedules(scheduleData);
    } catch {
      // Error handling can be added here if needed
    } finally {
      setLoading(false);
    }
  };

  const loadSchedules = async (routeId) => {
    if (!routeId) {
      setSchedules([]);
      return;
    }

    try {
      let scheduleData = [];
      
      for (let i = 0; i < 7; i++) {
        const date = new Date();
        date.setDate(date.getDate() + i);
        
        try {
          const daySchedules = await FirebaseService.getSchedulesForRoute(routeId, date);
          scheduleData = [...scheduleData, ...daySchedules];
        } catch {
          // Error handling can be added here if needed
        }
      }
      
      if (scheduleData.length === 0) {
        scheduleData = allSchedules.filter(schedule => {
          const routeMatch = schedule.routeId === routeId || 
                           schedule.route === routeId ||
                           schedule.routeName === routes.find(r => r.id === routeId)?.name;
          
          const scheduleTime = schedule.departureTime?.toDate ? 
            schedule.departureTime.toDate() : 
            new Date(schedule.departureTime);
          const isFuture = scheduleTime > new Date();
          
          return routeMatch && isFuture;
        });
      }
      
      const sortedSchedules = scheduleData.sort((a, b) => {
        const timeA = a.departureTime?.toDate ? a.departureTime.toDate() : new Date(a.departureTime);
        const timeB = b.departureTime?.toDate ? b.departureTime.toDate() : new Date(b.departureTime);
        return timeA - timeB;
      });
      
      setSchedules(sortedSchedules);
    } catch {
      const filteredSchedules = allSchedules.filter(schedule => {
        const routeMatch = schedule.routeId === routeId;
        const isFuture = schedule.departureTime?.toDate ? 
          schedule.departureTime.toDate() > new Date() : 
          new Date(schedule.departureTime) > new Date();
        return routeMatch && isFuture;
      });
      setSchedules(filteredSchedules);
    }
  };

  const bookTicket = async () => {
    if (!name || !phone || !selectedSchedule) {
      alert('Please fill all required fields');
      return;
    }
    
    try {
      const route = routes.find(r => r.id === selectedRoute);
      const ticketNumber = generateTicketNumber(tickets);
        
      const ticketData = {
        ticketNumber,
        passengerName: name,
        phoneNumber: phone,
        phone: phone,
        routeId: selectedRoute,
        routeName: route.name,
        busNumber: selectedSchedule.busNumber,
        departureTime: selectedSchedule.departureTime,
        fare: parseFloat(route.fare) || 0,
        price: parseFloat(route.fare) || 0,
        amount: parseFloat(route.fare) || 0,
        isUsed: false,
        status: 'booked',
        companyId: 'COMPANY_001',
        origin: route.origin,
        destination: route.destination,
        bookingDate: new Date().toISOString(),
        travelDate: selectedSchedule.departureTime,
      };

      const result = await FirebaseService.createTicket(ticketData);
        
      setBookedTicket({
        ...ticketData,
        id: result.id,
        route: route,
        schedule: selectedSchedule
      });
      setShowTicketPreview(true);
      
      alert('Ticket booked successfully! You can now print it below.');
      await loadData();
      
      setName('');
      setPhone('');
      setSelectedSchedule(null);
      setSelectedRoute('');
      handlePrint(); // Automatically trigger print after booking
    } catch (err) {
      alert('Booking failed: ' + err.message);
    }
  };

  if (loading) return <div className="p-6">Loading...</div>;

  return (
    <div className="p-6 max-w-4xl mx-auto">
      <h1 className="text-3xl font-bold mb-8">Book a Ticket</h1>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mb-8">
        <select 
          value={selectedRoute} 
          onChange={(e) => { 
            setSelectedRoute(e.target.value); 
            setSelectedSchedule(null);
            setShowTicketPreview(false);
            loadSchedules(e.target.value); 
          }} 
          className="p-3 border rounded"
        >
          <option value="">Select Route</option>
          {routes.map(r => (
            <option key={r.id} value={r.id}>
              {r.name} - GH₵{r.fare}
            </option>
          ))}
        </select>
        
        <select 
          value={selectedSchedule?.id || ''} 
          onChange={(e) => {
            const schedule = schedules.find(s => s.id === e.target.value);
            setSelectedSchedule(schedule);
            setShowTicketPreview(false);
          }} 
          className="p-3 border rounded" 
          disabled={!selectedRoute}
        >
          <option value="">
            {!selectedRoute ? 'Select Route First' : 
             schedules.length === 0 ? 'No Available Schedules' : 
             'Select Departure Time'}
          </option>
          {schedules.map(s => {
            const dep = s.departureTime?.toDate ? 
              s.departureTime.toDate().toLocaleString() : 
              new Date(s.departureTime).toLocaleString();
            return (
              <option key={s.id} value={s.id}>
                {s.busNumber} - {dep}
              </option>
            );
          })}
        </select>
        
        <input 
          type="text" 
          placeholder="Full Name *" 
          value={name} 
          onChange={(e) => setName(e.target.value)} 
          className="p-3 border rounded" 
          required
        />
        
        <input 
          type="tel" 
          placeholder="Phone Number *" 
          value={phone} 
          onChange={(e) => setPhone(e.target.value)} 
          className="p-3 border rounded" 
          required
        />
      </div>
      
      <div className="flex gap-4 mb-8">
        <button 
          onClick={bookTicket} 
          className="bg-green-600 text-white px-6 py-3 rounded-lg disabled:bg-gray-400"
          disabled={!name || !phone || !selectedSchedule}
        >
          Book Ticket
        </button>
        
        {selectedSchedule && name && phone && !showTicketPreview && (
          <button 
            onClick={() => {
              const route = routes.find(r => r.id === selectedRoute);
              setBookedTicket({
                ticketNumber: generateTicketNumber(tickets),
                passengerName: name,
                phoneNumber: phone,
                routeName: route.name,
                busNumber: selectedSchedule.busNumber,
                departureTime: selectedSchedule.departureTime,
                fare: route.fare,
                route: route,
                schedule: selectedSchedule
              });
              setShowTicketPreview(true);
            }} 
            className="bg-blue-600 text-white px-6 py-3 rounded-lg"
          >
            Preview Ticket
          </button>
        )}
      </div>

      {showTicketPreview && bookedTicket && (
        <div className="mb-8">
          <div className="bg-yellow-50 border-l-4 border-yellow-400 p-4 mb-4">
            <p className="text-yellow-700">
              <strong>Preview Mode:</strong> This shows how your ticket will look. 
              {!tickets.some(t => t.ticketNumber === bookedTicket.ticketNumber) ? 
                ' Click "Book Ticket" to save it to the database first.' : 
                ' This ticket has been saved and is ready to print.'}
            </p>
          </div>
          
          <div className="flex flex-col items-center gap-4">
            <div ref={componentRef} className="bg-white p-8 rounded-xl shadow-lg border-2 border-blue-200 max-w-md w-full">
              <div className="text-center">
                <h2 className="text-2xl font-bold mb-6 text-blue-900">Bus E-Ticket</h2>
                
                <div className="mb-6">
                  <QRCode 
                    value={`${bookedTicket.ticketNumber}-${bookedTicket.passengerName}`} 
                    size={120}
                    className="mx-auto" 
                  />
                </div>
                
                <div className="space-y-3 text-left">
                  <div className="border-b pb-2">
                    <p className="text-sm text-gray-600">Ticket Number</p>
                    <p className="font-bold text-lg">{bookedTicket.ticketNumber}</p>
                  </div>
                  
                  <div className="border-b pb-2">
                    <p className="text-sm text-gray-600">Passenger Name</p>
                    <p className="font-semibold">{bookedTicket.passengerName}</p>
                  </div>
                  
                  <div className="border-b pb-2">
                    <p className="text-sm text-gray-600">Route</p>
                    <p className="font-semibold">{bookedTicket.routeName}</p>
                  </div>
                  
                  <div className="border-b pb-2">
                    <p className="text-sm text-gray-600">Bus Number</p>
                    <p className="font-semibold">{bookedTicket.busNumber}</p>
                  </div>
                  
                  <div className="border-b pb-2">
                    <p className="text-sm text-gray-600">Departure Time</p>
                    <p className="font-semibold">
                      {bookedTicket.departureTime?.toDate ? 
                        bookedTicket.departureTime.toDate().toLocaleString() : 
                        new Date(bookedTicket.departureTime).toLocaleString()
                      }
                    </p>
                  </div>

                  {bookedTicket.expiresAt && (
                    <div className="border-b pb-2">
                      <p className="text-sm text-gray-600">Expires At</p>
                      <p className="font-semibold text-red-600">
                        {bookedTicket.expiresAt?.toDate ? 
                          bookedTicket.expiresAt.toDate().toLocaleString() : 
                          new Date(bookedTicket.expiresAt).toLocaleString()
                        }
                      </p>
                    </div>
                  )}
                  
                  <div className="border-b pb-2">
                    <p className="text-sm text-gray-600">Fare</p>
                    <p className="font-bold text-green-600 text-lg">GH₵{bookedTicket.fare}</p>
                  </div>
                  
                  <div className="border-b pb-2">
                    <p className="text-sm text-gray-600">Phone</p>
                    <p className="font-semibold">{bookedTicket.phoneNumber}</p>
                  </div>
                </div>
                
                <div className="mt-6 text-center">
                  <p className="text-xs text-gray-500">
                    Present this ticket at the boarding point. Keep your ticket safe.
                  </p>
                </div>
              </div>
            </div>
            
            <button 
              onClick={handlePrint}
              className="bg-blue-600 text-white px-6 py-3 rounded-lg hover:bg-blue-700 flex items-center gap-2"
              disabled={!tickets.some(t => t.ticketNumber === bookedTicket.ticketNumber)}
            >
              <Printer className="h-4 w-4" />
              Print Ticket
            </button>
            
            <button 
              onClick={() => {
                setShowTicketPreview(false);
                setBookedTicket(null);
              }}
              className="bg-gray-600 text-white px-6 py-3 rounded-lg hover:bg-gray-700"
            >
              Close Preview
            </button>
          </div>
        </div>
      )}

      {/* Recent Tickets Section */}
      <div className="mt-12">
        <h2 className="text-2xl font-bold mb-4">Recent Tickets</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {tickets.slice(-6).reverse().map((t) => (
            <div key={t.id} className="bg-white p-6 rounded-lg shadow-md border">
              <div className="flex items-start justify-between mb-4">
                <div>
                  <h3 className="font-bold text-lg">{t.passengerName}</h3>
                  <p className="text-sm text-gray-600">{t.routeName}</p>
                </div>
                <div className="text-right">
                  <span className="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-green-100 text-green-800">
                    {t.status}
                  </span>
                </div>
              </div>
              <div className="space-y-2 mb-4">
                <div className="flex items-center justify-between">
                  <span className="text-sm text-gray-600">Ticket #</span>
                  <span className="font-mono text-sm">{t.ticketNumber}</span>
                </div>
                {t.busNumber && (
                  <div className="flex items-center justify-between">
                    <span className="text-sm text-gray-600">Bus</span>
                    <span className="font-semibold">{t.busNumber}</span>
                  </div>
                )}
                {t.departureTime && (
                  <div className="flex items-center justify-between">
                    <span className="text-sm text-gray-600">Departure</span>
                    <span className="text-sm">{new Date(t.departureTime.toDate()).toLocaleString()}</span>
                  </div>
                )}
                {t.seatNumber && (
                  <p className="text-sm text-gray-600">Seat: {t.seatNumber}</p>
                )}
              </div>
              <div className="text-right">
                <div className="flex items-center text-gray-600 text-sm mb-1">
                  <Phone className="h-3 w-3 mr-1" />
                  {t.phoneNumber}
                </div>
                {t.fare && (
                  <div className="text-green-600 font-semibold text-sm mb-2">
                    GH₵{t.fare}
                  </div>
                )}
                <div className="flex space-x-2">
                  <span className={`px-2 py-1 rounded text-xs font-medium ${
                    t.isUsed ? 'bg-red-100 text-red-800' : 'bg-green-100 text-green-800'
                  }`}>
                    {t.isUsed ? 'Used' : 'Valid'}
                  </span>
                  {t.currentSession && (
                    <span className="px-2 py-1 rounded text-xs font-medium bg-blue-100 text-blue-800">
                      In Use
                    </span>
                  )}
                </div>
              </div>
              <div className="flex items-center text-xs text-gray-500 mt-2">
                <Calendar className="h-3 w-3 mr-1" />
                {new Date(t.createdAt.toDate()).toLocaleString()}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

export function ComplaintPage() {
  const [name, setName] = useState("");
  const [ticketNo, setTicketNo] = useState("");
  const [complaint, setComplaint] = useState("");
  const [complaints, setComplaints] = useState([]);
  const [submitted, setSubmitted] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [statusFilter, setStatusFilter] = useState("all");
  const [sourceFilter, setSourceFilter] = useState("all");

  useEffect(() => {
    const unsubscribe = FirebaseService.subscribeToComplaints((complaintsData) => {
      const enhancedComplaints = complaintsData.map(complaint => {
        let displayName = complaint.name || 'Anonymous';
        
        if (displayName.includes('@safecommute.gh')) {
          const ticketNumber = displayName.split('@')[0];
          displayName = complaint.passengerName || `Passenger (${ticketNumber})`;
        }
        
        return {
          ...complaint,
          displayName,
          hasTicket: !!complaint.ticketNumber,
          isFromMobile: complaint.source === 'mobile',
          hasPhoneNumber: !!(complaint.phoneNumber || complaint.phone),
        };
      });
      
      const sortedComplaints = enhancedComplaints.sort((a, b) => {
        const dateA = new Date(a.createdAt || a.timestamp || 0);
        const dateB = new Date(b.createdAt || b.timestamp || 0);
        return dateB - dateA;
      });
      setComplaints(sortedComplaints);
    });

    return () => {
      unsubscribe();
    };
  }, []);

  const submit = async () => {
    if (!name.trim() || !complaint.trim()) {
      setError("Name and complaint are required");
      return;
    }

    setLoading(true);
    setError("");

    try {
      await FirebaseService.createComplaint({
        name: name.trim(),
        ticketNumber: ticketNo.trim() || null,
        complaint: complaint.trim(),
        status: 'pending',
        source: 'web',
        companyId: 'COMPANY_001'
      });

      setName(""); 
      setTicketNo(""); 
      setComplaint("");
      setSubmitted(true);
      setTimeout(() => setSubmitted(false), 3000);
    } catch {
      setError("Failed to submit complaint. Please try again.");
    } finally {
      setLoading(false);
    }
  };

  const filteredComplaints = complaints.filter(complaint => {
    const matchesStatus = statusFilter === "all" || complaint.status === statusFilter;
    const matchesSource = sourceFilter === "all" || complaint.source === sourceFilter;
    return matchesStatus && matchesSource;
  });

  return (
    <div className="p-6 max-w-6xl mx-auto">
      <div className="mb-8">
        <h1 className="text-3xl font-bold text-gray-900 mb-2">Submit a Complaint</h1>
        <p className="text-gray-600">Report issues and track complaint resolution</p>
      </div>

      <div className="bg-white p-6 rounded-xl shadow-lg mb-8">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-4">
          <input 
            type="text" 
            placeholder="Your Name" 
            value={name} 
            onChange={(e) => setName(e.target.value)} 
            className="p-3 border rounded" 
          />
          <input 
            type="text" 
            placeholder="Ticket Number (optional)" 
            value={ticketNo} 
            onChange={(e) => setTicketNo(e.target.value)} 
            className="p-3 border rounded" 
          />
          <div className="flex gap-2">
            <select 
              value={statusFilter} 
              onChange={(e) => setStatusFilter(e.target.value)} 
              className="flex-1 p-3 border rounded"
            >
              <option value="all">All Status</option>
              <option value="pending">Pending</option>
              <option value="resolved">Resolved</option>
            </select>
            <select 
              value={sourceFilter} 
              onChange={(e) => setSourceFilter(e.target.value)} 
              className="flex-1 p-3 border rounded"
            >
              <option value="all">All Sources</option>
              <option value="mobile">Mobile</option>
              <option value="web">Web</option>
            </select>
          </div>
        </div>
        <textarea
          placeholder="Describe your complaint..."
          value={complaint}
          onChange={(e) => setComplaint(e.target.value)}
          className="w-full p-3 border rounded h-32"
          rows={4}
        />
        <button 
          onClick={submit} 
          disabled={loading} 
          className="bg-red-600 text-white px-6 py-3 rounded-lg mt-4 hover:bg-red-700 disabled:bg-gray-400"
        >
          {loading ? 'Submitting...' : 'Submit Complaint'}
        </button>
        {error && <p className="text-red-600 mt-2">{error}</p>}
        {submitted && <p className="text-green-600 mt-2">Complaint submitted successfully!</p>}
      </div>

      <div className="mb-4">
        <h2 className="text-2xl font-bold mb-4">Complaints ({filteredComplaints.length})</h2>
        <div className="bg-gray-50 p-3 rounded-lg text-sm text-gray-600">
          {complaints.filter(c => c.status === 'pending').length} pending • {' '}
          {complaints.filter(c => c.status === 'resolved').length} resolved • {' '}
          {complaints.filter(c => c.isFromMobile).length} from mobile • {' '}
          {complaints.filter(c => !c.isFromMobile).length} from web
        </div>
      </div>

      <div className="space-y-4">
        {filteredComplaints.length === 0 ? (
          <div className="bg-white p-8 rounded-lg shadow text-center">
            <AlertCircle className="h-12 w-12 text-gray-400 mx-auto mb-4" />
            <h3 className="text-lg font-medium text-gray-900 mb-2">No Complaints Found</h3>
            <p className="text-gray-500">No complaints match your current filters.</p>
          </div>
        ) : (
          filteredComplaints.map((c) => (
            <div key={c.id} className="bg-white rounded-lg shadow-md hover:shadow-lg transition-shadow">
              <div className="p-6">
                <div className="flex flex-col md:flex-row md:items-start md:justify-between gap-4">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-start gap-3 mb-3">
                      <div className="flex-shrink-0">
                        <div className={`w-10 h-10 rounded-full flex items-center justify-center ${
                          c.isFromMobile ? 'bg-green-100' : 'bg-blue-100'
                        }`}>
                          {c.isFromMobile ? (
                            <Smartphone className="h-5 w-5 text-green-600" />
                          ) : (
                            <Monitor className="h-5 w-5 text-blue-600" />
                          )}
                        </div>
                      </div>
                      
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 mb-1">
                          <h3 className="font-semibold text-gray-900 truncate">
                            {c.displayName}
                          </h3>
                          <span className={`inline-flex items-center px-2 py-1 rounded-full text-xs font-medium ${
                            c.status === 'pending' ? 'bg-yellow-100 text-yellow-800' :
                            c.status === 'resolved' ? 'bg-green-100 text-green-800' :
                            'bg-gray-100 text-gray-800'
                          }`}>
                            {c.status}
                          </span>
                        </div>
                        
                        <div className="flex flex-wrap items-center gap-4 text-sm text-gray-500 mb-2">
                          {c.hasPhoneNumber && (
                            <div className="flex items-center gap-1">
                              <Phone className="h-3 w-3" />
                              <span>{c.phoneNumber || c.phone}</span>
                            </div>
                          )}
                          
                          {c.hasTicket && (
                            <div className="flex items-center gap-1">
                              <span className="font-mono text-xs bg-gray-100 px-2 py-1 rounded">
                                {c.ticketNumber}
                              </span>
                            </div>
                          )}
                          
                          {c.busNumber && (
                            <div className="flex items-center gap-1">
                              <span className="text-xs bg-blue-100 text-blue-800 px-2 py-1 rounded">
                                Bus: {c.busNumber}
                              </span>
                            </div>
                          )}
                          
                          {c.routeName && (
                            <div className="flex items-center gap-1">
                              <span className="text-xs bg-purple-100 text-purple-800 px-2 py-1 rounded">
                                {c.routeName}
                              </span>
                            </div>
                          )}
                        </div>
                      </div>
                    </div>
                    
                    <div className="bg-gray-50 p-4 rounded-lg mb-3">
                      <p className="text-gray-700 leading-relaxed">{c.complaint}</p>
                    </div>
                    
                    {(c.origin || c.destination) && (
                      <div className="text-sm text-gray-500 mb-3">
                        <strong>Route:</strong> {c.origin} → {c.destination}
                      </div>
                    )}
                    
                    <div className="flex items-center gap-4 text-xs text-gray-400">
                      <div className="flex items-center gap-1">
                        <Calendar className="h-3 w-3" />
                        <span>
                          {new Date(c.createdAt?.toDate ? c.createdAt.toDate() : c.timestamp).toLocaleString()}
                        </span>
                      </div>
                      
                      <div className="flex items-center gap-1">
                        {c.isFromMobile ? <Smartphone className="h-3 w-3" /> : <Monitor className="h-3 w-3" />}
                        <span>{c.source === 'mobile' ? 'Mobile App' : 'Web Portal'}</span>
                      </div>
                    </div>
                  </div>
                  
                  <div className="flex flex-col gap-2 md:ml-4">
                    {c.status === 'resolved' && (
                      <div className="flex items-center gap-1 text-green-600 text-sm">
                        <CheckCircle className="h-4 w-4" />
                        <span>Resolved</span>
                      </div>
                    )}
                  </div>
                </div>
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
}