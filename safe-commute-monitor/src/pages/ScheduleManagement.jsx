import React, { useState, useEffect } from 'react';
import { Calendar, Bus, Clock, Save } from 'lucide-react';
import { FirebaseService } from '../services/firebaseService';

export function ScheduleManagement() {
  const [routes, setRoutes] = useState([]);
  const [buses, setBuses] = useState([]);
  const [schedules, setSchedules] = useState([]);
  const [selectedRoute, setSelectedRoute] = useState('');
  const [selectedBus, setSelectedBus] = useState('');
  const [departureTime, setDepartureTime] = useState(new Date().toISOString().slice(0, 16));
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadData();
  }, []);

  const loadData = async () => {
    try {
      const [routeData, busData, scheduleData] = await Promise.all([
        FirebaseService.getRoutes(),
        FirebaseService.getBuses(),
        FirebaseService.getSchedules()
      ]);
      
      setRoutes(routeData);
      setBuses(busData);
      setSchedules(scheduleData);
    } catch {
      // Removed console.error('Error loading data:', err);
    } finally {
      setLoading(false);
    }
  };

  const assignSchedule = async () => {
    if (!selectedRoute || !selectedBus || !departureTime) {
      alert('Please fill all fields');
      return;
    }
    try {
      await FirebaseService.assignSchedule(selectedRoute, selectedBus, new Date(departureTime));
      alert('Schedule assigned successfully!');
      loadData(); // Refresh
      setSelectedBus('');
      setDepartureTime(new Date().toISOString().slice(0, 16));
    } catch (err) {
      alert('Error: ' + err.message);
    }
  };

  const filteredBuses = buses.filter(b => {
    const showAllBuses = true;
    
    if (showAllBuses) {
      return b.isActive === true; // Only filter by active status
    }
    
    const routeMatch = b.routeId === selectedRoute || 
                      b.route === selectedRoute || 
                      b.assignedRoute === selectedRoute ||
                      !b.routeId; // Unassigned buses
    
    const isAvailable = b.isAvailable === true || 
                       b.available === true || 
                       b.status === 'available' ||
                       !Object.prototype.hasOwnProperty.call(b, 'isAvailable');
    
    return routeMatch && isAvailable;
  });

  if (loading) return <div className="p-6">Loading...</div>;

  return (
    <div className="p-6 max-w-6xl mx-auto">
      <h1 className="text-3xl font-bold mb-8">Schedule Management</h1>

      <div className="bg-white p-6 rounded-xl shadow-lg mb-8">
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
          <select 
            value={selectedRoute} 
            onChange={(e) => {
              setSelectedRoute(e.target.value);
              setSelectedBus(''); // Reset bus selection
            }} 
            className="p-3 border rounded"
          >
            <option value="">Select Route</option>
            {routes.map(r => <option key={r.id} value={r.id}>{r.name}</option>)}
          </select>
          
          <select 
            value={selectedBus} 
            onChange={(e) => setSelectedBus(e.target.value)} 
            className="p-3 border rounded" 
            disabled={!selectedRoute}
          >
            <option value="">
              {!selectedRoute ? 'Select Route First' : 
               filteredBuses.length === 0 ? 'No Available Buses' : 
               'Select Available Bus'}
            </option>
            {filteredBuses.map(b => (
              <option key={b.id} value={b.id}>
                {b.busNumber || b.number || b.plateNumber || `Bus ${b.id}`}
              </option>
            ))}
          </select>
          
          <input 
            type="datetime-local" 
            value={departureTime} 
            onChange={(e) => setDepartureTime(e.target.value)} 
            className="p-3 border rounded" 
          />
          
          <button 
            onClick={assignSchedule} 
            className="bg-blue-600 text-white p-3 rounded flex items-center justify-center"
            disabled={!selectedRoute || !selectedBus || !departureTime}
          >
            <Save className="h-5 w-5 mr-2" /> Assign
          </button>
        </div>
      </div>

      <h2 className="text-2xl font-bold mb-4">Current Schedules</h2>
      <div className="bg-white rounded-xl shadow-lg overflow-hidden">
        <table className="w-full">
          <thead className="bg-gray-50">
            <tr>
              <th className="p-3 text-left">Route</th>
              <th className="p-3 text-left">Bus</th>
              <th className="p-3 text-left">Departure</th>
              <th className="p-3 text-left">Status</th>
            </tr>
          </thead>
          <tbody>
            {schedules.map(s => (
              <tr key={s.id} className="border-t">
                <td className="p-3">{s.routeName}</td>
                <td className="p-3">{s.busNumber}</td>
                <td className="p-3">
                  {s.departureTime?.toDate ? 
                    new Date(s.departureTime.toDate()).toLocaleString() :
                    new Date(s.departureTime).toLocaleString()
                  }
                </td>
                <td className="p-3">
                  <span className={`px-2 py-1 rounded text-xs ${
                    s.status === 'scheduled' ? 'bg-yellow-100 text-yellow-800' :
                    s.status === 'in_transit' ? 'bg-blue-100 text-blue-800' :
                    'bg-green-100 text-green-800'
                  }`}>
                    {s.status}
                  </span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}