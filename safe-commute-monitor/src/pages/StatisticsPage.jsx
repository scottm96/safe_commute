import React, { useState, useEffect } from 'react';
import { BarChart, Bar, LineChart, Line, PieChart, Pie, Cell, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import { TrendingUp, TrendingDown, DollarSign, FileText, AlertCircle, CheckCircle, Calendar, Users, RefreshCw } from 'lucide-react';
import { FirebaseService } from '../services/firebaseService';

const COLORS = ['#0088FE', '#00C49F', '#FFBB28', '#FF8042', '#8884d8'];

export function StatisticsPage() {
  const [ticketStats, setTicketStats] = useState({ daily: null, weekly: null, monthly: null, yearly: null });
  const [complaintStats, setComplaintStats] = useState(null);
  const [revenueData, setRevenueData] = useState([]);
  const [loading, setLoading] = useState(true);
  const [selectedPeriod, setSelectedPeriod] = useState('monthly');
  const [error, setError] = useState(null);

  useEffect(() => {
    loadStatistics();
  }, []);

  const loadStatistics = async () => {
    setLoading(true);
    setError(null);
    
    try {
      // Load statistics with better error handling for each
      const results = await Promise.allSettled([
        FirebaseService.getTicketStatistics('daily'),
        FirebaseService.getTicketStatistics('weekly'),
        FirebaseService.getTicketStatistics('monthly'),
        FirebaseService.getTicketStatistics('yearly'),
        FirebaseService.getComplaintStatistics(),
        FirebaseService.getRevenueByPeriod(30)
      ]);

      const [dailyTickets, weeklyTickets, monthlyTickets, yearlyTickets, complaints, revenue] = results;

      // Handle each result individually
      setTicketStats({
        daily: dailyTickets.status === 'fulfilled' ? dailyTickets.value : { tickets: [] },
        weekly: weeklyTickets.status === 'fulfilled' ? weeklyTickets.value : { tickets: [] },
        monthly: monthlyTickets.status === 'fulfilled' ? monthlyTickets.value : { tickets: [] },
        yearly: yearlyTickets.status === 'fulfilled' ? yearlyTickets.value : { tickets: [] }
      });

      setComplaintStats(complaints.status === 'fulfilled' ? complaints.value : {
        totalComplaints: 0,
        pendingComplaints: 0,
        resolvedComplaints: 0,
        mobileComplaints: 0,
        webComplaints: 0
      });

      setRevenueData(revenue.status === 'fulfilled' ? revenue.value : []);

      // Check for any failures
      const failures = results.filter(r => r.status === 'rejected');
      if (failures.length > 0) {
        setError(`Some data couldn't be loaded. ${failures.length} requests failed.`);
      }
    } catch (err) {
      const errorMsg = 'Failed to load statistics: ' + err.message;
      setError(errorMsg);
    } finally {
      setLoading(false);
    }
  };

  const formatCurrency = (amount) => {
    return new Intl.NumberFormat('en-GH', { 
      style: 'currency', 
      currency: 'GHS' 
    }).format(amount || 0);
  };

  const getTotalTickets = () => {
    return ticketStats.yearly?.tickets?.reduce((sum, t) => sum + (t.count || 0), 0) || 0;
  };

  const getTotalRevenue = () => {
    return revenueData.reduce((sum, r) => sum + (r.revenue || 0), 0);
  };

  const getCurrentPeriodData = () => {
    const data = ticketStats[selectedPeriod];
    if (!data || !data.tickets || data.tickets.length === 0) {
      return [];
    }
    return data.tickets;
  };

  if (loading) {
    return (
      <div className="p-6 text-center">
        <div className="animate-spin rounded-full h-32 w-32 border-b-2 border-blue-600 mx-auto mb-4"></div>
        <p className="text-lg">Loading statistics...</p>
      </div>
    );
  }

  return (
    <div className="p-6 max-w-7xl mx-auto">
      <div className="flex justify-between items-center mb-8">
        <h1 className="text-3xl font-bold">Statistics Dashboard - Ghana InterCity Trans</h1>
      </div>

      {error && (
        <div className="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">
          {error}
        </div>
      )}

      {/* Key Metrics */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
        <div className="bg-white p-6 rounded-xl shadow-lg text-center">
          <DollarSign className="h-12 w-12 text-green-600 mx-auto mb-4" />
          <h3 className="text-xl font-bold text-gray-900">Total Revenue (30 days)</h3>
          <p className="text-3xl font-bold text-green-600">{formatCurrency(getTotalRevenue())}</p>
          <p className="text-sm text-gray-500 mt-1">{revenueData.length} data points</p>
        </div>
        <div className="bg-white p-6 rounded-xl shadow-lg text-center">
          <FileText className="h-12 w-12 text-blue-600 mx-auto mb-4" />
          <h3 className="text-xl font-bold text-gray-900">Total Tickets</h3>
          <p className="text-3xl font-bold text-blue-600">{getTotalTickets()}</p>
          <p className="text-sm text-gray-500 mt-1">All time</p>
        </div>
        <div className="bg-white p-6 rounded-xl shadow-lg text-center">
          <AlertCircle className="h-12 w-12 text-yellow-600 mx-auto mb-4" />
          <h3 className="text-xl font-bold text-gray-900">Pending Complaints</h3>
          <p className="text-3xl font-bold text-yellow-600">{complaintStats?.pendingComplaints || 0}</p>
          <p className="text-sm text-gray-500 mt-1">Needs attention</p>
        </div>
        <div className="bg-white p-6 rounded-xl shadow-lg text-center">
          <CheckCircle className="h-12 w-12 text-green-600 mx-auto mb-4" />
          <h3 className="text-xl font-bold text-gray-900">Resolved Complaints</h3>
          <p className="text-3xl font-bold text-green-600">{complaintStats?.resolvedComplaints || 0}</p>
          <p className="text-sm text-gray-500 mt-1">Completed</p>
        </div>
      </div>

      {/* Complaints Pie Chart */}
      {complaintStats && complaintStats.totalComplaints > 0 && (
        <div className="bg-white p-6 rounded-xl shadow-lg mb-8">
          <h3 className="text-lg font-bold text-gray-900 mb-4">Complaints Overview</h3>
          <ResponsiveContainer width="100%" height={300}>
            <PieChart>
              <Pie
                data={[
                  { name: 'Pending', value: complaintStats.pendingComplaints },
                  { name: 'Resolved', value: complaintStats.resolvedComplaints }
                ].filter(item => item.value > 0)}
                cx="50%" cy="50%" outerRadius={80} fill="#8884d8" dataKey="value" nameKey="name"
              >
                <Cell fill="#FFBB28" />
                <Cell fill="#00C49F" />
              </Pie>
              <Tooltip formatter={(value) => [value, 'Count']} />
              <Legend />
            </PieChart>
          </ResponsiveContainer>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mt-4">
            <div className="text-center p-4 bg-blue-50 rounded-lg">
              <Users className="h-8 w-8 text-blue-600 mx-auto mb-2" />
              <p className="text-2xl font-bold text-blue-600">{complaintStats.mobileComplaints}</p>
              <p className="text-sm text-gray-600">Mobile App</p>
            </div>
            <div className="text-center p-4 bg-green-50 rounded-lg">
              <FileText className="h-8 w-8 text-green-600 mx-auto mb-2" />
              <p className="text-2xl font-bold text-green-600">{complaintStats.webComplaints}</p>
              <p className="text-sm text-gray-600">Web Dashboard</p>
            </div>
            <div className="text-center p-4 bg-purple-50 rounded-lg">
              <AlertCircle className="h-8 w-8 text-purple-600 mx-auto mb-2" />
              <p className="text-2xl font-bold text-purple-600">{complaintStats.totalComplaints}</p>
              <p className="text-sm text-gray-600">Total Complaints</p>
            </div>
          </div>
        </div>
      )}

      {/* Tickets Trend Line Chart */}
      <div className="bg-white p-6 rounded-xl shadow-lg mb-8">
        <div className="flex justify-between items-center mb-4">
          <h3 className="text-lg font-bold text-gray-900">
            Tickets Sold & Revenue ({selectedPeriod})
            <span className="text-sm text-gray-500 ml-2">
              ({getCurrentPeriodData().length} data points)
            </span>
          </h3>
          <select 
            value={selectedPeriod} 
            onChange={(e) => setSelectedPeriod(e.target.value)} 
            className="p-2 border rounded"
          >
            <option value="daily">Daily</option>
            <option value="weekly">Weekly</option>
            <option value="monthly">Monthly</option>
            <option value="yearly">Yearly</option>
          </select>
        </div>
        
        {getCurrentPeriodData().length > 0 ? (
          <ResponsiveContainer width="100%" height={300}>
            <LineChart data={getCurrentPeriodData()}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="date" />
              <YAxis yAxisId="left" />
              <YAxis yAxisId="right" orientation="right" />
              <Tooltip formatter={(value, name, props) => {
                if (name === 'Tickets' || props?.dataKey === 'count') {
                  return [value, 'Tickets'];
                } else if (name === 'Revenue' || props?.dataKey === 'revenue') {
                  return [formatCurrency(value), 'Revenue'];
                }
                return [value, name];
              }} />
              <Legend />
              <Line yAxisId="left" type="monotone" dataKey="count" stroke="#8884d8" name="Tickets" />
              <Line yAxisId="right" type="monotone" dataKey="revenue" stroke="#82ca9d" name="Revenue" />
            </LineChart>
          </ResponsiveContainer>
        ) : (
          <div className="text-center py-12 text-gray-500">
            <FileText className="h-16 w-16 mx-auto mb-4 opacity-50" />
            <p className="text-lg">No ticket data available for {selectedPeriod} period</p>
            <p className="text-sm mt-2">Tickets may not have the correct structure or date range</p>
          </div>
        )}
      </div>

      {/* Revenue Bar Chart */}
      <div className="bg-white p-6 rounded-xl shadow-lg mb-8">
        <h3 className="text-lg font-bold text-gray-900 mb-4">Revenue Generated</h3>
        {revenueData.length > 0 ? (
          <ResponsiveContainer width="100%" height={300}>
            <BarChart data={revenueData}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="period" />
              <YAxis />
              <Tooltip formatter={(value) => [formatCurrency(value), 'Revenue']} />
              <Legend />
              <Bar dataKey="revenue" fill="#82ca9d" />
            </BarChart>
          </ResponsiveContainer>
        ) : (
          <div className="text-center py-12 text-gray-500">
            <DollarSign className="h-16 w-16 mx-auto mb-4 opacity-50" />
            <p className="text-lg">No revenue data available</p>
            <p className="text-sm mt-2">Check if tickets have fare/price fields</p>
          </div>
        )}
      </div>

      {/* Bottom Stats Bar */}
      <div className="bg-gradient-to-r from-blue-600 to-purple-600 text-white p-6 rounded-xl shadow-lg mt-8 relative overflow-hidden">
        <div style={{
          position: 'absolute',
          bottom: 0,
          left: 0,
          right: 0,
          height: '50%',
          background: 'linear-gradient(to top, black 0%, transparent 100%)'
        }} />
        <div className="relative z-10 flex items-center justify-between">
          <div className="flex-1">
            <h3 className="text-lg font-bold mb-2">System Status</h3>
            <p className="opacity-90">Last update: {new Date().toLocaleString()}</p>
          </div>
          <div className="text-right">
            <div className="flex items-center mb-1">
              <FileText className="h-5 w-5 mr-1" />
              <span className="text-sm">{getTotalTickets()} total tickets</span>
            </div>
            <div className="flex items-center">
              <DollarSign className="h-5 w-5 mr-1" />
              <span className="text-sm">{formatCurrency(getTotalRevenue())} total revenue</span>
            </div>
          </div>
        </div>
      </div>

      {/* Refresh Button */}
      <div className="text-center mt-8">
        <button
          onClick={loadStatistics}
          disabled={loading}
          className="bg-blue-600 text-white px-6 py-3 rounded-lg hover:bg-blue-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center mx-auto"
        >
          {loading ? (
            <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-white mr-2"></div>
          ) : (
            <RefreshCw className="h-4 w-4 mr-2" />
          )}
          {loading ? 'Refreshing...' : 'Refresh Statistics'}
        </button>
      </div>
    </div>
  );
}