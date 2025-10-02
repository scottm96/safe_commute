import React from "react";
import { BrowserRouter as Router, Routes, Route, Link, Navigate } from "react-router-dom";
import BusTrackingMap from "./pages/BusTrackingMap";
import { TicketPage, ComplaintPage } from "./pages/TicketPage"; // Updated TicketPage to BookingManagement
import { StatisticsPage } from "./pages/StatisticsPage";
import { ScheduleManagement } from "./pages/ScheduleManagement";

// Simple staff auth stub (in production, use Firebase Auth)
const StaffLogin = () => {
  const [isLoggedIn, setIsLoggedIn] = React.useState(false); // Simulate login
  return isLoggedIn ? <Navigate to="/staff/schedules" /> : (
    <div className="p-6">
      <h2>Staff Login</h2>
      <button onClick={() => setIsLoggedIn(true)} className="bg-blue-600 text-white px-4 py-2 rounded">Login as Staff</button>
    </div>
  );
};

export default function App() {
  return (
    <Router>
      <nav style={{ padding: 12, background: "#0f172a", color: "#fff" }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', maxWidth: '1200px', margin: '0 auto' }}>
          <div style={{ display: 'flex', alignItems: 'center' }}>
            <h1 style={{ margin: '0 20px 0 0', fontSize: '20px', fontWeight: 'bold' }}>Ghana InterCity Trans</h1>
          </div>
          <div style={{ display: 'flex', gap: '20px' }}>
            <Link to="/" style={{ color: "#fff", textDecoration: 'none', padding: '8px 16px', borderRadius: '6px', backgroundColor: 'rgba(255,255,255,0.1)' }}>
              Live Map
            </Link>
            <Link to="/tickets" style={{ color: "#fff", textDecoration: 'none', padding: '8px 16px', borderRadius: '6px', backgroundColor: 'rgba(255,255,255,0.1)' }}>
              Bookings
            </Link>
            <Link to="/complaints" style={{ color: "#fff", textDecoration: 'none', padding: '8px 16px', borderRadius: '6px', backgroundColor: 'rgba(255,255,255,0.1)' }}>
              Complaints
            </Link>
            <Link to="/statistics" style={{ color: "#fff", textDecoration: 'none', padding: '8px 16px', borderRadius: '6px', backgroundColor: 'rgba(255,255,255,0.1)' }}>
              Statistics
            </Link>
            <Link to="/schedules" style={{ color: "#fff", textDecoration: 'none', padding: '8px 16px', borderRadius: '6px', backgroundColor: 'rgba(255,255,255,0.1)' }}>
              Staff Portal
            </Link>
          </div>
        </div>
      </nav>

      <Routes>
        <Route path="/" element={<BusTrackingMap />} />
        <Route path="/tickets" element={<TicketPage />} />
        <Route path="/complaints" element={<ComplaintPage />} />
        <Route path="/statistics" element={<StatisticsPage />} />
        
        <Route path="/schedules" element={<ScheduleManagement />} />
      </Routes>
    </Router>
  );
}