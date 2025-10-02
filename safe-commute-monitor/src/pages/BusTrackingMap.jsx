import { useState, useEffect } from "react";
import { MapContainer, TileLayer, Marker, Popup, useMap, Polyline } from "react-leaflet";
import { Navigation, MapPin, Clock, Users, Zap, AlertTriangle, Search, Filter } from "lucide-react";
import "leaflet/dist/leaflet.css";
import L from "leaflet";
import { FirebaseService } from "../services/firebaseService";

// Fix for default markers in React Leaflet
delete L.Icon.Default.prototype._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-icon-2x.png",
  iconUrl: "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-icon.png",
  shadowUrl: "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-shadow.png",
});

// Custom bus icons based on status
const createBusIcon = (status) => {
  const colors = {
    active: "#10B981", // Green
    idle: "#F59E0B",   // Yellow
    maintenance: "#EF4444", // Red
    drowsy: "#F97316", // Orange
  };

  const iconHtml = `
    <div style="
      width: 40px;
      height: 40px;
      border-radius: 50%;
      background: ${colors[status] || colors.active};
      border: 3px solid white;
      box-shadow: 0 4px 12px rgba(0,0,0,0.3);
      display: flex;
      align-items: center;
      justify-content: center;
      position: relative;
    ">
      <div style="
        width: 20px;
        height: 20px;
        background: white;
        border-radius: 4px;
        display: flex;
        align-items: center;
        justify-content: center;
      ">
        🚌
      </div>
      ${status === 'drowsy' ? `<div style="
        position: absolute;
        top: -5px;
        right: -5px;
        width: 12px;
        height: 12px;
        background: #EF4444;
        border-radius: 50%;
        border: 2px solid white;
      "></div>` : ''}
    </div>
  `;

  return L.divIcon({
    html: iconHtml,
    className: 'custom-bus-icon',
    iconSize: [40, 40],
    iconAnchor: [20, 20],
  });
};

// Component to handle map interactions
function MapController({ selectedBus, buses, routes }) {
  const map = useMap();

  useEffect(() => {
    if (selectedBus && buses[selectedBus]) {
      const bus = buses[selectedBus];
      map.setView([bus.location?.latitude || 5.6037, bus.location?.longitude || -0.1870], 16, { animate: true });
    }
  }, [selectedBus, buses, map]);

  // Draw route polylines if coordinates available (assume routes have sample coords)
  const routePolylines = routes.map(route => {
    // Sample coords for routes (replace with real if in DB)
    let coords = [];
    switch (route.id) {
      case 'A-K': coords = [[5.6037, -0.1870], [6.6666, -1.6163]]; break; // Accra to Kumasi
      case 'A-T': coords = [[5.6037, -0.1870], [9.4034, -0.8444]]; break; // Accra to Tamale
      // Add more
      default: coords = [[5.6037, -0.1870], [5.6037, -0.1870]];
    }
    return (
      <Polyline
        key={route.id}
        positions={coords}
        color="#8884d8"
        weight={3}
        opacity={0.7}
      />
    );
  });

  return (
    <>
      {routePolylines}
    </>
  );
}

export default function BusTrackingMap() {
  const [/*drivers*/, setDrivers] = useState({});
  const [buses, setBuses] = useState({});
  const [routes, setRoutes] = useState([]);
  const [selectedBus, setSelectedBus] = useState(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [filterStatus, setFilterStatus] = useState('all');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const loadData = async () => {
      try {
        // Fetch real routes from Firestore
        const routeData = await FirebaseService.getRoutes();
        setRoutes(routeData);

        // Subscribe to real-time driver status (assumes subscribeToDrivers fetches from driver_status)
        const unsubscribeDrivers = FirebaseService.subscribeToDrivers((driverData) => {
          const driverMap = {};
          driverData.forEach(d => {
            driverMap[d.id] = d;
          });
          setDrivers(driverMap);

          // Map to buses (group by busNumber)
          const busMap = {};
          driverData.forEach(d => {
            if (d.busNumber) {
              // Match route name from routes
              const matchedRoute = routeData.find(r => r.id === d.currentRoute || d.routeId);
              busMap[d.busNumber] = { 
                ...d, 
                routeName: matchedRoute ? matchedRoute.name : 'Unknown Route',
                location: d.location 
              };
            }
          });
          setBuses(busMap);
        });

        return () => unsubscribeDrivers();
      } catch {
        // Removed console.error('Error loading data:', error);
      } finally {
        setLoading(false);
      }
    };

    loadData();
  }, []);

  const filteredBuses = Object.values(buses).filter(bus => 
    bus.busNumber.toLowerCase().includes(searchTerm.toLowerCase()) &&
    (filterStatus === 'all' || bus.status === filterStatus)
  );

  // Group buses by route for sidebar
  const busesByRoute = {};
  filteredBuses.forEach(bus => {
    const routeKey = bus.routeName || 'Unknown Route';
    if (!busesByRoute[routeKey]) busesByRoute[routeKey] = [];
    busesByRoute[routeKey].push(bus);
  });

  const getStatusText = (status) => status.charAt(0).toUpperCase() + status.slice(1);
  const getStatusColor = (status) => {
    switch (status) {
      case 'active': return 'bg-green-100 text-green-800';
      case 'idle': return 'bg-yellow-100 text-yellow-800';
      case 'maintenance': return 'bg-red-100 text-red-800';
      case 'drowsy': return 'bg-orange-100 text-orange-800';
      default: return 'bg-gray-100 text-gray-800';
    }
  };
  const getAlertLevelText = (level) => level.charAt(0).toUpperCase() + level.slice(1);

  if (loading) return <div className="p-6 text-center">Loading buses and routes...</div>;

  return (
    <div className="flex h-screen bg-gray-100">
      {/* Sidebar - Grouped by Real Routes */}
      <div className="w-80 bg-white shadow-lg overflow-y-auto">
        <div className="p-4 border-b">
          <h2 className="text-xl font-bold">Bus Tracking (Real Routes)</h2>
          <div className="flex gap-2 mt-2">
            <input
              type="text"
              placeholder="Search buses..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="flex-1 p-2 border rounded"
            />
            <select value={filterStatus} onChange={(e) => setFilterStatus(e.target.value)} className="p-2 border rounded">
              <option value="all">All Status</option>
              <option value="active">Active</option>
              <option value="idle">Idle</option>
              <option value="maintenance">Maintenance</option>
              <option value="drowsy">Drowsy Alert</option>
            </select>
          </div>
        </div>
        <div className="p-4">
          {Object.entries(busesByRoute).length === 0 ? (
            <p className="text-gray-500">No buses on routes found.</p>
          ) : (
            <div className="space-y-4">
              {Object.entries(busesByRoute).map(([routeName, routeBuses]) => (
                <div key={routeName}>
                  <h3 className="font-semibold text-gray-800 mb-2">{routeName} ({routeBuses.length} buses)</h3>
                  <ul className="space-y-2">
                    {routeBuses.map((bus) => (
                      <li key={bus.driverId} className="p-3 border rounded-lg cursor-pointer hover:bg-gray-50" onClick={() => setSelectedBus(bus.busNumber)}>
                        <div className="flex justify-between items-start">
                          <div>
                            <h4 className="font-semibold">{bus.busNumber}</h4>
                            <p className="text-sm text-gray-600">Route: {routeName}</p>
                          </div>
                          <span className={`inline-flex items-center px-2 py-1 rounded-full text-xs font-medium ${getStatusColor(bus.status)}`}>
                            {bus.status === 'drowsy' && <AlertTriangle className="h-3 w-3 mr-1" />}
                            {getStatusText(bus.status)}
                          </span>
                        </div>
                      </li>
                    ))}
                  </ul>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {/* Map */}
      <div className="flex-1 relative">
        <MapContainer center={[5.6037, -0.1870]} zoom={13} style={{ height: '100%', width: '100%' }}>
          <TileLayer url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" />
          {Object.values(buses).map((bus) => (
            <Marker
              key={bus.driverId}
              position={[bus.location?.latitude || 5.6037, bus.location?.longitude || -0.1870]}
              icon={createBusIcon(bus.status)}
            >
              <Popup>
                <div className="min-w-64">
                  <h3 className="font-bold">{bus.busNumber}</h3>
                  <div className="space-y-2 text-sm">
                    <div className="flex items-center justify-between">
                      <span className="flex items-center">
                        <MapPin className="h-4 w-4 mr-1 text-gray-500" />
                        Location:
                      </span>
                      <span>{bus.location?.latitude?.toFixed(4)}, {bus.location?.longitude?.toFixed(4)}</span>
                    </div>
                    <div className="flex items-center justify-between">
                      <span className="flex items-center">
                        <Users className="h-4 w-4 mr-1 text-gray-500" />
                        Passengers:
                      </span>
                      <span>{bus.passengerCount || 0}</span>
                    </div>
                    <div className="flex items-center justify-between">
                      <span className="flex items-center">
                        <Clock className="h-4 w-4 mr-1 text-gray-500" />
                        Updated:
                      </span>
                      <span className="font-medium">
                        {new Date(bus.lastUpdate).toLocaleTimeString()}
                      </span>
                    </div>
                    
                    {bus.alertLevel && bus.alertLevel !== 'none' && (
                      <div className="flex items-center justify-between">
                        <span className="flex items-center">
                          <AlertTriangle className="h-4 w-4 mr-1 text-orange-500" />
                          Alert Level:
                        </span>
                        <span className="font-medium text-orange-600">
                          {getAlertLevelText(bus.alertLevel)}
                        </span>
                      </div>
                    )}
                    
                    {bus.closedEyeFrames > 0 && (
                      <div className="flex items-center justify-between">
                        <span className="text-xs text-orange-600">
                          Closed eye frames:
                        </span>
                        <span className="font-medium text-orange-600">
                          {bus.closedEyeFrames}
                        </span>
                      </div>
                    )}
                  </div>
                  
                  <div className="mt-3 pt-2 border-t border-gray-200">
                    <span className={`inline-flex items-center px-2 py-1 rounded-full text-xs font-medium text-white ${getStatusColor(bus.status)}`}>
                      {bus.status === 'drowsy' && <AlertTriangle className="h-3 w-3 mr-1" />}
                      {getStatusText(bus.status)}
                    </span>
                    
                    {bus.status === 'drowsy' && (
                      <p className="text-xs text-orange-600 mt-1 font-medium">
                        Driver attention alert triggered!
                      </p>
                    )}
                    
                    {!bus.isOnline && (
                      <p className="text-xs text-red-600 mt-1 font-medium">
                        Driver is offline
                      </p>
                    )}
                  </div>
                </div>
              </Popup>
            </Marker>
          ))}
          <MapController selectedBus={selectedBus} buses={buses} routes={routes} />
        </MapContainer>
      </div>
    </div>
  );
}