import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppData {
  // Central Rooms List with beds matching residents
  static List<Map<String, dynamic>> rooms = [
    {
      'number': '101',
      'floor': 'Ground Floor',
      'type': '3-Sharing',
      'beds': <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'Bed A',
          'status': 'Occupied',
          'occupant': 'Siddarth Mishra',
          'rent': 8000,
          'dob': '22/08/1996',
          'gender': 'Male',
          'occupation': 'Product Designer',
          'email': 'siddarth.m@example.com',
          'emergency_contact': '9876543298',
          'address': 'B-302, Green Glen Layout, Bellandur, Bengaluru',
          'pincode': '560103',
          'aadhaar_number': '7823 4590 1234',
          'pan_number': 'XYZPM9876K',
        },
        <String, dynamic>{
          'name': 'Bed B',
          'status': 'Occupied',
          'occupant': 'Priya Sharma',
          'rent': 8000,
          'dob': '15/05/1998',
          'gender': 'Female',
          'occupation': 'Software Engineer',
          'email': 'priya.sharma@example.com',
          'emergency_contact': '9876543299',
          'address': '#14, 2nd Cross, Indira Nagar, Bengaluru',
          'pincode': '560038',
          'aadhaar_number': '4512 8923 7104',
          'pan_number': 'ABCPS1234F',
        },
        <String, dynamic>{
          'name': 'Bed C',
          'status': 'Available',
          'occupant': null,
          'rent': 8000,
        },
      ],
    },
    {
      'number': '102',
      'floor': 'Ground Floor',
      'type': '2-Sharing',
      'beds': <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'Bed A',
          'status': 'Occupied',
          'occupant': 'Anna Ben',
          'rent': 7000,
          'dob': '19/09/1999',
          'gender': 'Female',
          'occupation': 'UI/UX Designer',
          'email': 'anna.ben@example.com',
          'emergency_contact': '9876543295',
          'address': 'House 88, BTM 2nd Stage, Bengaluru',
          'pincode': '560076',
          'aadhaar_number': '6789 0123 4567',
          'pan_number': 'ABPAN5555Z',
        },
        <String, dynamic>{
          'name': 'Bed B',
          'status': 'Available',
          'occupant': null,
          'rent': 7000,
        },
      ],
    },
    {
      'number': '201',
      'floor': '1st Floor',
      'type': '2-Sharing',
      'beds': <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'Bed A',
          'status': 'Occupied',
          'occupant': 'Pradeep Kumar',
          'rent': 8000,
          'dob': '10/11/1997',
          'gender': 'Male',
          'occupation': 'Data Analyst',
          'email': 'pradeep.k@example.com',
          'emergency_contact': '9876543297',
          'address': 'Flat 101, Lakeview Apts, HSR Layout, Bengaluru',
          'pincode': '560102',
          'aadhaar_number': '3456 7890 1234',
          'pan_number': 'LMNOP5678Q',
        },
        <String, dynamic>{
          'name': 'Bed B',
          'status': 'Available',
          'occupant': null,
          'rent': 8000,
        },
      ],
    },
    {
      'number': '301',
      'floor': '2nd Floor',
      'type': '1-Sharing (Single)',
      'beds': <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'Bed A',
          'status': 'Occupied',
          'occupant': 'David Joseph',
          'rent': 10000,
          'dob': '03/04/1995',
          'gender': 'Male',
          'occupation': 'Marketing Manager',
          'email': 'david.j@example.com',
          'emergency_contact': '9876543296',
          'address': '12/A, Koramangala 4th Block, Bengaluru',
          'pincode': '560034',
          'aadhaar_number': '9012 3456 7890',
          'pan_number': 'DJDJD4321R',
        },
      ],
    },
  ];

  // Central list to hold self-registered residents awaiting approval
  static List<Map<String, dynamic>> pendingResidents = [];

  // Central mock admin notifications list for self-registered residents
  static List<Map<String, dynamic>> adminNotifications = [];

  // Central Residents List
  static List<Map<String, dynamic>> residents = [
    {
      'name': 'Rohan Mehta',
      'phone': '9876543290',
      'room_number': null,
      'room': null,
      'bed': null,
      'rent': 8000,
      'deposit': 16000,
      'kyc': 'Under Review',
      'status': 'Pending',
      'email': 'rohan.mehta@example.com',
      'dob': '12/04/1997',
      'gender': 'Male',
      'occupation': 'Software Consultant',
      'emergency_contact': '9812345678',
      'address': 'Flat 402, Sunrise Towers, HSR Layout, Bengaluru',
      'pincode': '560102',
      'document_type': 'Passport',
      'document_image_url': 'https://images.unsplash.com/photo-1589829545856-d10d557cf95f?w=400',
      'selfie_url': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400',
      'property_name': 'BNR Luxury PG',
      'joining_date': 'Today',
      'role': 'Resident',
    },
    {
      'name': 'Priya Sharma',
      'phone': '9876543210',
      'room_number': '101',
      'room': '101',
      'bed': 'Bed B',
      'rent': 8000,
      'deposit': 16000,
      'kyc': 'Verified',
      'status': 'Active',
      'email': 'priya.sharma@example.com',
      'dob': '15/05/1998',
      'gender': 'Female',
      'occupation': 'Software Engineer',
      'emergency_contact': '9876543299',
      'address': '#14, 2nd Cross, Indira Nagar, Bengaluru',
      'pincode': '560038',
      'document_type': 'Aadhaar',
      'document_image_url': 'https://images.unsplash.com/photo-1544717305-2782549b5136?w=400',
      'selfie_url': 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=400',
      'aadhaar_number': '4512 8923 7104',
      'pan_number': 'ABCPS1234F',
      'property_name': 'Green View PG - Hebbal',
      'joining_date': '01 Jan 2026',
      'role': 'Resident',
    },
    {
      'name': 'Siddarth Mishra',
      'phone': '9876543211',
      'room': '101',
      'bed': 'Bed A',
      'rent': 8000,
      'deposit': 16000,
      'kyc': 'Verified',
      'status': 'Active',
      'email': 'siddarth.m@example.com',
      'dob': '22/08/1996',
      'gender': 'Male',
      'occupation': 'Product Designer',
      'emergency_contact': '9876543298',
      'address': 'B-302, Green Glen Layout, Bellandur, Bengaluru',
      'pincode': '560103',
      'aadhaar_number': '7823 4590 1234',
      'pan_number': 'XYZPM9876K',
      'property_name': 'Green View PG - Hebbal',
      'joining_date': '15 Feb 2026',
      'role': 'Resident',
    },
    {
      'name': 'Pradeep Kumar',
      'phone': '9876543212',
      'room': '201',
      'bed': 'Bed A',
      'rent': 8000,
      'deposit': 8000,
      'kyc': 'Pending',
      'status': 'Notice Period',
      'email': 'pradeep.k@example.com',
      'dob': '10/11/1997',
      'gender': 'Male',
      'occupation': 'Data Analyst',
      'emergency_contact': '9876543297',
      'address': 'Flat 101, Lakeview Apts, HSR Layout, Bengaluru',
      'pincode': '560102',
      'aadhaar_number': '3456 7890 1234',
      'pan_number': 'LMNOP5678Q',
      'property_name': 'Green View PG - Hebbal',
      'joining_date': '01 Mar 2026',
      'role': 'Resident',
    },
    {
      'name': 'David Joseph',
      'phone': '9876543213',
      'room': '301',
      'bed': 'Bed A',
      'rent': 10000,
      'deposit': 20000,
      'kyc': 'Verified',
      'status': 'Active',
      'email': 'david.j@example.com',
      'dob': '03/04/1995',
      'gender': 'Male',
      'occupation': 'Marketing Manager',
      'emergency_contact': '9876543296',
      'address': '12/A, Koramangala 4th Block, Bengaluru',
      'pincode': '560034',
      'aadhaar_number': '9012 3456 7890',
      'pan_number': 'DJDJD4321R',
      'property_name': 'BNR Luxury PG',
      'joining_date': '10 Mar 2026',
      'role': 'Resident',
    },
    {
      'name': 'Anna Ben',
      'phone': '9876543214',
      'room': '102',
      'bed': 'Bed A',
      'rent': 7000,
      'deposit': 14000,
      'kyc': 'Rejected',
      'status': 'Checked Out',
      'email': 'anna.ben@example.com',
      'dob': '19/09/1999',
      'gender': 'Female',
      'occupation': 'UI/UX Designer',
      'emergency_contact': '9876543295',
      'address': 'House 88, BTM 2nd Stage, Bengaluru',
      'pincode': '560076',
      'aadhaar_number': '6789 0123 4567',
      'pan_number': 'ABPAN5555Z',
      'property_name': 'Green View PG - Hebbal',
      'joining_date': '05 Apr 2026',
      'role': 'Resident',
    },
  ];

  // Helper to find resident by name
  static Map<String, dynamic>? getResidentByName(String name) {
    final clean = name.trim().toLowerCase();
    final index = residents.indexWhere((r) => r['name'].toString().trim().toLowerCase() == clean);
    if (index != -1) return residents[index];
    return null;
  }

  // Central Property Selection
  static List<String> propertyNames = [
    'Green View PG - Hebbal',
    'BNR Luxury PG',
    'Skyline Girls PG',
    'Silicon Oasis PG - HSR Layout',
    'Green Nest PG',
  ];
  static String selectedProperty = 'Green View PG - Hebbal';
  static String? selectedPropertyId;
  static final ValueNotifier<String?> selectedPropertyIdNotifier = ValueNotifier<String?>(null);

  static void setRealProperties(List<Map<String, dynamic>> backendProps) {
    if (backendProps.isEmpty) return;
    properties = backendProps;
    propertyNames = backendProps.map((p) => p['name']?.toString() ?? 'Unnamed').toList();
    if (selectedPropertyId == null || !backendProps.any((p) => p['id']?.toString() == selectedPropertyId)) {
      selectedPropertyId = backendProps.first['id']?.toString();
      selectedProperty = backendProps.first['name']?.toString() ?? '';
    } else {
      final current = backendProps.firstWhere(
        (p) => p['id']?.toString() == selectedPropertyId,
        orElse: () => backendProps.first,
      );
      selectedProperty = current['name']?.toString() ?? '';
    }
    selectedPropertyIdNotifier.value = selectedPropertyId;
  }

  static void selectPropertyByName(String name) {
    selectedProperty = name;
    final match = properties.firstWhere(
      (p) => p['name']?.toString() == name,
      orElse: () => properties.isNotEmpty ? properties.first : {'id': null},
    );
    selectedPropertyId = match['id']?.toString();
    selectedPropertyIdNotifier.value = selectedPropertyId;
  }

  // Room selected from Dashboard Room Availability to highlight in Rooms & Beds screen
  static String? selectedRoomForHighlight;

  // Central Properties List matching the full schema
  static List<Map<String, dynamic>> properties = [
    {
      'id': 'p1',
      'name': 'BNR Luxury PG',
      'city': 'Bengaluru',
      'pincode': '560095',
      'address': 'Koramangala 4th Block, Near Sony Signal',
      'floors': 4,
      'propertyType': 'PG',
      'type': 'Co-Living',
      'occupancyType': 'Co-Living',
      'rooms': 45,
      'beds': 140,
      'status': 'Active',
      'ownerName': 'Ramesh BNR',
      'ownerContact': '9876543210',
      'ownerEmail': 'ramesh.bnr@example.com',
      'managerName': 'Rajesh Kumar',
      'managerContact': '9876543210',
      'amenities': [
        'High Speed Wi-Fi',
        '3 Times Daily Meals',
        'Washing Machine',
        'Daily Housekeeping',
        'RO Drinking Water',
        'CCTV & Biometric Security',
        '24/7 Power Backup',
        'Common Lounge & TV',
        'AC / Cooler',
        'Parking',
      ],
    },
    {
      'id': 'p2',
      'name': 'Skyline Girls PG',
      'city': 'Bengaluru',
      'pincode': '560102',
      'address': 'HSR Layout Sector 2, 14th Main',
      'floors': 3,
      'propertyType': 'PG',
      'type': 'Girls',
      'occupancyType': 'Girls',
      'rooms': 30,
      'beds': 90,
      'status': 'Active',
      'ownerName': 'Suresh Reddy',
      'ownerContact': '9876543215',
      'ownerEmail': 'suresh.reddy@example.com',
      'managerName': 'Sunil Gowda',
      'managerContact': '9876543216',
      'amenities': [
        'High Speed Wi-Fi',
        '3 Times Daily Meals',
        'Daily Housekeeping',
        'RO Drinking Water',
        'CCTV & Biometric Security',
        '24/7 Power Backup',
        'Common Lounge & TV',
      ],
    },
    {
      'id': 'p3',
      'name': 'Silicon Oasis PG - HSR Layout',
      'city': 'Bengaluru',
      'pincode': '560102',
      'address': 'Sector 2, 27th Main Rd, HSR Layout',
      'floors': 3,
      'propertyType': 'PG',
      'type': 'Boys',
      'occupancyType': 'Boys',
      'rooms': 10,
      'beds': 18,
      'status': 'Active',
      'ownerName': 'Arun Sharma',
      'ownerContact': '9876543220',
      'ownerEmail': 'arun.sharma@example.com',
      'managerName': 'Manjunath',
      'managerContact': '9876543221',
      'amenities': [
        'High Speed Wi-Fi',
        '3 Times Daily Meals',
        'Washing Machine',
        'Daily Housekeeping',
        'RO Drinking Water',
        '24/7 Power Backup',
        'Parking',
      ],
    },
    {
      'id': 'p4',
      'name': 'Green Nest PG',
      'city': 'Hyderabad',
      'pincode': '500081',
      'address': 'Madhapur, Near Cyber Towers',
      'floors': 2,
      'propertyType': 'PG',
      'type': 'Boys',
      'occupancyType': 'Boys',
      'rooms': 20,
      'beds': 60,
      'status': 'Maintenance',
      'ownerName': 'Venkat Rao',
      'ownerContact': '9876543230',
      'ownerEmail': 'venkat.rao@example.com',
      'managerName': 'Kishore',
      'managerContact': '9876543231',
      'amenities': [
        'High Speed Wi-Fi',
        'Daily Housekeeping',
        'RO Drinking Water',
        '24/7 Power Backup',
        'Parking',
      ],
    },
  ];

  // Central Invoices List
  static List<Map<String, dynamic>> invoices = [
    {
      'id': 'INV-2026-001',
      'name': 'Siddarth Mishra',
      'phone': '9876543211',
      'property': 'Green View PG - Hebbal',
      'room': 'Room 101',
      'month': '2026-09',
      'expected': 8000,
      'paid': 8000,
      'amount': 8000,
      'status': 'Paid',
      'payment_mode': 'UPI',
      'ref_id': 'TXN-984321',
      'date': '01 Oct 2026',
    },
    {
      'id': 'INV-2026-002',
      'name': 'Pradeep Kumar',
      'phone': '9876543212',
      'property': 'Green View PG - Hebbal',
      'room': 'Room 201',
      'month': '2026-09',
      'expected': 8000,
      'paid': 4000,
      'amount': 8000,
      'status': 'Partial',
      'payment_mode': 'Cash',
      'ref_id': 'CSH-1042',
      'date': '01 Oct 2026',
    },
    {
      'id': 'INV-2026-003',
      'name': 'David Joseph',
      'phone': '9876543213',
      'property': 'BNR Luxury PG',
      'room': 'Room 301',
      'month': '2026-09',
      'expected': 10000,
      'paid': 0,
      'amount': 10000,
      'status': 'Overdue',
      'payment_mode': 'Pending',
      'ref_id': '-',
      'date': '01 Sep 2026',
    },
    {
      'id': 'INV-2026-004',
      'name': 'Anna Ben',
      'phone': '9876543214',
      'property': 'Green View PG - Hebbal',
      'room': 'Room 102',
      'month': '2026-09',
      'expected': 7000,
      'paid': 7000,
      'amount': 7000,
      'status': 'Paid',
      'payment_mode': 'Bank Transfer',
      'ref_id': 'NEFT-55129',
      'date': '01 Oct 2026',
    },
    {
      'id': 'INV-2026-005',
      'name': 'Priya Sharma',
      'phone': '9876543210',
      'property': 'Green View PG - Hebbal',
      'room': 'Room 101',
      'month': '2026-09',
      'expected': 8000,
      'paid': 0,
      'amount': 8000,
      'status': 'Pending',
      'payment_mode': 'Pending',
      'ref_id': '-',
      'date': '01 Oct 2026',
    },
  ];

  // Centralized Staff List (persists across navigation)
  static List<Map<String, dynamic>> staff = [
    {'name': 'Ramesh Kumar', 'role': 'Warden', 'phone': '9876543210', 'salary': '25000', 'status': 'Active'},
    {'name': 'Sita Devi', 'role': 'Housekeeping', 'phone': '9876543211', 'salary': '15000', 'status': 'Active'},
    {'name': 'John Doe', 'role': 'Security', 'phone': '9876543212', 'salary': '18000', 'status': 'On Leave'},
  ];

  // Centralized Leads List (persists across navigation)
  static List<Map<String, dynamic>> leads = [
    {'name': 'Rahul Sharma', 'phone': '9876500001', 'source': 'Walk-in', 'status': 'New', 'date': 'Today'},
    {'name': 'Amit Verma', 'phone': '9876500002', 'source': 'Instagram', 'status': 'Visit Scheduled', 'date': 'Yesterday'},
    {'name': 'Neha Singh', 'phone': '9876500003', 'source': 'Referral', 'status': 'Contacted', 'date': '2 days ago'},
    {'name': 'Vikram Rao', 'phone': '9876500004', 'source': 'MagicBricks', 'status': 'Lost', 'date': 'Last week'},
  ];

  // Centralized Complaints List (persists across navigation)
  static List<Map<String, dynamic>> complaints = [
    {
      'id': 'CMP-001',
      'title': 'AC cooling malfunctioning',
      'description': 'Compressor cuts off repeatedly after 10 mins',
      'category': 'Appliance',
      'resident': 'Siddarth Mishra',
      'room': '101',
      'property': 'Green View PG - Hebbal',
      'priority': 'High',
      'assigned_staff': 'Ramesh (Electrician)',
      'status': 'Assigned',
      'date': '24 Oct 2026',
    },
    {
      'id': 'CMP-002',
      'title': 'Water leakage under washbasin',
      'description': 'Slow drip causing pool in bathroom',
      'category': 'Plumbing',
      'resident': 'Anna Ben',
      'room': '102',
      'property': 'Green View PG - Hebbal',
      'priority': 'Medium',
      'assigned_staff': 'Suresh (Plumber)',
      'status': 'In Progress',
      'date': '23 Oct 2026',
    },
    {
      'id': 'CMP-003',
      'title': 'Wi-Fi fiber connection drop',
      'description': 'Signal weak on 3rd floor west wing',
      'category': 'Internet',
      'resident': 'David Joseph',
      'room': '301',
      'property': 'BNR Luxury PG',
      'priority': 'Low',
      'assigned_staff': 'Kiran (Network Tech)',
      'status': 'Resolved',
      'date': '22 Oct 2026',
    },
    {
      'id': 'CMP-004',
      'title': 'Room deep cleaning request',
      'description': 'Post festival cleaning and trash disposal',
      'category': 'Cleaning',
      'resident': 'Priya Sharma',
      'room': '101',
      'property': 'Green View PG - Hebbal',
      'priority': 'Low',
      'assigned_staff': 'Sunita (Housekeeping)',
      'status': 'Resolved',
      'date': '21 Oct 2026',
    },
    {
      'id': 'CMP-005',
      'title': 'Geyser water not heating',
      'description': 'Tripping main MCB when switched on',
      'category': 'Electrical',
      'resident': 'Pradeep Kumar',
      'room': '201',
      'property': 'Green View PG - Hebbal',
      'priority': 'High',
      'assigned_staff': 'Ramesh (Electrician)',
      'status': 'Assigned',
      'date': '20 Oct 2026',
    },
  ];

  // Centralized Other Expenses (persists across navigation)
  static List<Map<String, dynamic>> otherExpenses = [
    {
      'date': '24 Oct 2026',
      'category': 'Utilities',
      'description': 'BESCOM Electricity Bill - Main Meter',
      'amount': 12500,
      'property': 'Green View PG - Hebbal',
    },
    {
      'date': '20 Oct 2026',
      'category': 'Utilities',
      'description': 'BWSSB & Private Water Tanker (3 Loads)',
      'amount': 4500,
      'property': 'Green View PG - Hebbal',
    },
    {
      'date': '16 Oct 2026',
      'category': 'Internet',
      'description': 'Airtel Fiber 300 Mbps Commercial Plan',
      'amount': 2800,
      'property': 'BNR Luxury PG',
    },
    {
      'date': '12 Oct 2026',
      'category': 'Maintenance',
      'description': 'Plumbing repairs in 2nd Floor Washrooms',
      'amount': 3200,
      'property': 'Green View PG - Hebbal',
    },
    {
      'date': '05 Oct 2026',
      'category': 'Food & Supplies',
      'description': 'Monthly Grocery & Rice Supplies from Metro',
      'amount': 18000,
      'property': 'Green View PG - Hebbal',
    },
  ];

  // Centralized Employee Salaries (persists across navigation)
  static List<Map<String, dynamic>> employeeSalaries = [
    {
      'name': 'Ramesh Kumar',
      'role': 'Head Cook',
      'payment_date': '01 Oct 2026',
      'salary_month': 'September 2026',
      'amount': 22000,
      'property': 'Green View PG - Hebbal',
    },
    {
      'name': 'Sunita Devi',
      'role': 'Housekeeping Staff',
      'payment_date': '01 Oct 2026',
      'salary_month': 'September 2026',
      'amount': 14000,
      'property': 'Green View PG - Hebbal',
    },
    {
      'name': 'Manoj Gowda',
      'role': 'Security Guard',
      'payment_date': '02 Oct 2026',
      'salary_month': 'September 2026',
      'amount': 16000,
      'property': 'BNR Luxury PG',
    },
    {
      'name': 'Venkatesh S',
      'role': 'Night Security',
      'payment_date': '02 Oct 2026',
      'salary_month': 'September 2026',
      'amount': 15000,
      'property': 'Skyline Girls PG',
    },
    {
      'name': 'Anil Rao',
      'role': 'PG Supervisor / Manager',
      'payment_date': '01 Oct 2026',
      'salary_month': 'September 2026',
      'amount': 28000,
      'property': 'Green View PG - Hebbal',
    },
  ];

  // Weekly Food Menu (Monday to Sunday)
  static List<Map<String, dynamic>> foodMenu = [
    {'day': 'Monday', 'breakfast': 'Poha & Tea', 'lunch': 'Dal, Rice, Roti, Sabzi', 'dinner': 'Paneer, Roti, Rice'},
    {'day': 'Tuesday', 'breakfast': 'Idli & Sambar', 'lunch': 'Rajma, Rice, Roti', 'dinner': 'Mix Veg, Roti, Rice'},
    {'day': 'Wednesday', 'breakfast': 'Aloo Paratha & Curd', 'lunch': 'Kadhi Pakoda, Rice, Roti', 'dinner': 'Aloo Gobi, Dal, Rice'},
    {'day': 'Thursday', 'breakfast': 'Upma & Chutney', 'lunch': 'Chole, Rice, Bhature/Roti', 'dinner': 'Egg Curry / Kofta, Rice'},
    {'day': 'Friday', 'breakfast': 'Puri Bhaji', 'lunch': 'Sambhar, Rice, Papad, Curd', 'dinner': 'Veg Biryani & Raita'},
    {'day': 'Saturday', 'breakfast': 'Dosa & Sambar', 'lunch': 'Dal Tadka, Jeera Rice, Roti', 'dinner': 'Special Thali / Paneer Butter Masala'},
    {'day': 'Sunday', 'breakfast': 'Chole Kulche / Halwa', 'lunch': 'Dum Biryani, Salan, Raita', 'dinner': 'Khichdi / Light Meal & Dessert'},
  ];

  // Function to load residents and notifications from browser memory
  static Future<void> loadResidentsFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load food menu
      String? storedFood = prefs.getString('demo_food_menu');
      if (storedFood != null) {
        List<dynamic> foodList = jsonDecode(storedFood);
        if (foodList.isNotEmpty) {
          foodMenu = foodList.map((e) => Map<String, dynamic>.from(e)).toList();
        }
      }

      // Load notifications
      String? storedNotifs = prefs.getString('demo_admin_notifications');
      if (storedNotifs != null) {
        List<dynamic> notifList = jsonDecode(storedNotifs);
        adminNotifications = notifList.map((e) => Map<String, dynamic>.from(e)).toList();
      }

      String? storedData = prefs.getString('demo_residents');
      if (storedData != null) {
        List<dynamic> decoded = jsonDecode(storedData);
        if (decoded.isNotEmpty) {
          final List<Map<String, dynamic>> loaded = [];
          for (var item in decoded) {
            final map = Map<String, dynamic>.from(item);
            final name = map['name']?.toString() ?? '';
            if (name.toLowerCase().contains('rahul')) continue;
            
            if (map['room_number'] == null && map['room'] != null) {
              map['room_number'] = map['room'];
            } else if (map['room'] == null && map['room_number'] != null) {
              map['room'] = map['room_number'];
            }
            if (map['status'] == null) {
              map['status'] = map['room_number'] != null ? 'Active' : 'Pending';
            }
            loaded.add(map);
          }
          if (loaded.isNotEmpty) {
            residents = loaded;
          }
        }
      }
    } catch (_) {}
  }

  // Function to save residents to browser memory
  static Future<void> saveResidentsToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('demo_residents', jsonEncode(residents));
      await prefs.setString('demo_admin_notifications', jsonEncode(adminNotifications));
    } catch (_) {}
  }

  // Function to save food menu to browser memory
  static Future<void> saveFoodMenuToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('demo_food_menu', jsonEncode(foodMenu));
    } catch (_) {}
  }

  // Function to save rooms to browser memory
  static Future<void> saveRoomsToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('demo_rooms', jsonEncode(rooms));
    } catch (_) {}
  }

  // Approve a pending self-registered resident and assign room & bed
  static String? approveAndAssignRoom({
    required String residentName,
    required String roomNumber,
    String? residentPhone,
    String? bedName,
  }) {
    final cleanName = residentName.trim();
    final cleanRoom = roomNumber.trim();
    final cleanRoomDigits = cleanRoom.replaceAll(RegExp(r'[^0-9]'), '');

    // 1. Find the target room (case-insensitive & digit matching)
    int roomIndex = rooms.indexWhere((r) {
      final rNum = r['number'].toString().trim().toLowerCase();
      final rDigits = rNum.replaceAll(RegExp(r'[^0-9]'), '');
      return rNum == cleanRoom.toLowerCase() ||
          (cleanRoomDigits.isNotEmpty && rDigits == cleanRoomDigits);
    });

    if (roomIndex == -1) {
      final newRoom = <String, dynamic>{
        'number': cleanRoom,
        'floor': cleanRoomDigits.startsWith('2')
            ? '1st Floor'
            : (cleanRoomDigits.startsWith('3') ? '2nd Floor' : 'Ground Floor'),
        'type': '2-Sharing',
        'beds': <Map<String, dynamic>>[
          {
            'name': 'Bed A',
            'status': 'Available',
            'occupant': null,
            'rent': 8000,
          },
          {
            'name': 'Bed B',
            'status': 'Available',
            'occupant': null,
            'rent': 8000,
          },
        ],
      };
      rooms.add(newRoom);
      roomIndex = rooms.length - 1;
    }

    // 2. Find available bed in that room
    final beds = rooms[roomIndex]['beds'] as List;
    int bedIndex = -1;
    if (bedName != null && bedName.isNotEmpty) {
      bedIndex = beds.indexWhere(
        (b) => b['name'].toString().toLowerCase() == bedName.toLowerCase() && b['status'] == 'Available',
      );
    }
    if (bedIndex == -1) {
      bedIndex = beds.indexWhere((b) => b['status'] == 'Available');
    }

    // If no available bed in this room, create a new available bed so admin can always assign!
    if (bedIndex == -1) {
      final nextChar = String.fromCharCode(65 + beds.length); // Bed A, B, C, D...
      final newBed = <String, dynamic>{
        'name': 'Bed $nextChar',
        'status': 'Available',
        'occupant': null,
        'rent': 8000,
      };
      try {
        (rooms[roomIndex]['beds'] as List).add(newBed);
        bedIndex = (rooms[roomIndex]['beds'] as List).length - 1;
      } catch (_) {
        rooms[roomIndex]['beds'] = (rooms[roomIndex]['beds'] as List)
            .map((b) => Map<String, dynamic>.from(b as Map))
            .toList();
        (rooms[roomIndex]['beds'] as List).add(newBed);
        bedIndex = (rooms[roomIndex]['beds'] as List).length - 1;
      }
    }

    // 3. Mark bed as occupied
    try {
      rooms[roomIndex]['beds'][bedIndex]['status'] = 'Occupied';
      rooms[roomIndex]['beds'][bedIndex]['occupant'] = cleanName;
    } catch (_) {
      rooms[roomIndex]['beds'] = (rooms[roomIndex]['beds'] as List)
          .map((b) => Map<String, dynamic>.from(b as Map))
          .toList();
      rooms[roomIndex]['beds'][bedIndex]['status'] = 'Occupied';
      rooms[roomIndex]['beds'][bedIndex]['occupant'] = cleanName;
    }

    final chosenBedName = rooms[roomIndex]['beds'][bedIndex]['name']?.toString() ?? 'Bed A';

    // 4. Update resident in central list (match by name or phone)
    final resIndex = residents.indexWhere((r) {
      final matchName = r['name']?.toString().trim().toLowerCase() == cleanName.toLowerCase();
      final matchPhone = residentPhone != null && residentPhone.isNotEmpty && r['phone']?.toString().trim() == residentPhone.trim();
      return matchName || matchPhone;
    });

    if (resIndex != -1) {
      residents[resIndex]['room'] = rooms[roomIndex]['number'].toString();
      residents[resIndex]['room_number'] = rooms[roomIndex]['number'].toString();
      residents[resIndex]['bed'] = chosenBedName;
      residents[resIndex]['status'] = 'Active';
      residents[resIndex]['kyc'] = 'Verified';
    } else {
      residents.insert(0, {
        'name': cleanName,
        'phone': residentPhone ?? '',
        'room': rooms[roomIndex]['number'].toString(),
        'room_number': rooms[roomIndex]['number'].toString(),
        'bed': chosenBedName,
        'status': 'Active',
        'kyc': 'Verified',
        'rent': 8000,
        'deposit': 16000,
        'joining_date': 'Today',
      });
    }

    // 5. Remove corresponding pending notification and pending resident
    adminNotifications.removeWhere((n) {
      final matchName = n['resident_name']?.toString().trim().toLowerCase() == cleanName.toLowerCase();
      final matchPhone = residentPhone != null && residentPhone.isNotEmpty && n['resident_phone']?.toString().trim() == residentPhone.trim();
      return matchName || matchPhone;
    });

    pendingResidents.removeWhere((p) {
      final matchName = p['name']?.toString().trim().toLowerCase() == cleanName.toLowerCase();
      final matchPhone = residentPhone != null && residentPhone.isNotEmpty && p['phone']?.toString().trim() == residentPhone.trim();
      return matchName || matchPhone;
    });

    saveResidentsToStorage();
    return null; // Success
  }

  // Rule 1: Check for Duplicate Rooms
  static bool roomExists(String roomNumber) {
    return rooms.any((r) => r['number'].toString().toLowerCase() == roomNumber.trim().toLowerCase());
  }

  // Rule 2: Assign Resident via Residents Screen, returns assigned bed name on success
  static String? assignResidentToRoom(
    String roomNumber, 
    String residentName, {
    String? phone,
    String? floor,
    int? rent,
    String? dueDate,
    String? Function(String bedName)? onBedAssigned,
    Map<String, dynamic>? residentData,
    String? dob,
    String? gender,
    String? occupation,
    String? email,
    String? emergencyContact,
    String? address,
    String? pincode,
    String? aadhaarNumber,
    String? panNumber,
    int? deposit,
  }) {
    final cleanRoom = roomNumber.trim();
    final cleanDigits = cleanRoom.replaceAll(RegExp(r'[^0-9]'), '');
    
    int roomIndex = rooms.indexWhere(
      (r) => r['number'].toString().trim().toLowerCase() == cleanRoom.toLowerCase() ||
             (cleanDigits.isNotEmpty && r['number'].toString().replaceAll(RegExp(r'[^0-9]'), '') == cleanDigits),
    );

    // If room doesn't exist, auto-create it with standard 2 beds
    if (roomIndex == -1) {
      final floorName = (floor != null && floor.trim().isNotEmpty)
          ? floor.trim()
          : (cleanDigits.startsWith('2')
              ? '1st Floor'
              : (cleanDigits.startsWith('3')
                  ? '2nd Floor'
                  : (cleanDigits.startsWith('4') ? '3rd Floor' : 'Ground Floor')));
      final newRoom = <String, dynamic>{
        'number': cleanRoom.isNotEmpty ? cleanRoom : '101',
        'floor': floorName,
        'type': '2-Sharing',
        'beds': <Map<String, dynamic>>[
          {
            'name': 'Bed A',
            'status': 'Available',
            'occupant': null,
            'rent': rent ?? 8000,
          },
          {
            'name': 'Bed B',
            'status': 'Available',
            'occupant': null,
            'rent': rent ?? 8000,
          },
        ],
      };
      rooms.add(newRoom);
      roomIndex = rooms.length - 1;
    }

    final room = rooms[roomIndex];
    var beds = room['beds'] as List;
    int bedIndex = beds.indexWhere((b) => b['status'] == 'Available');

    // If room is full, dynamically add another bed so onboarding never fails!
    if (bedIndex == -1) {
      final nextChar = String.fromCharCode(65 + beds.length);
      final newBed = <String, dynamic>{
        'name': 'Bed $nextChar',
        'status': 'Available',
        'occupant': null,
        'rent': rent ?? 8000,
      };
      try {
        beds.add(newBed);
        bedIndex = beds.length - 1;
      } catch (_) {
        room['beds'] = beds.map((b) => Map<String, dynamic>.from(b as Map)).toList();
        (room['beds'] as List).add(newBed);
        beds = room['beds'] as List;
        bedIndex = beds.length - 1;
      }
    }

    try {
      beds[bedIndex]['status'] = 'Occupied';
      beds[bedIndex]['occupant'] = residentName;
      beds[bedIndex]['dob'] = dob ?? residentData?['dob'];
      beds[bedIndex]['gender'] = gender ?? residentData?['gender'];
      beds[bedIndex]['occupation'] = occupation ?? residentData?['occupation'];
      beds[bedIndex]['email'] = email ?? residentData?['email'];
      beds[bedIndex]['emergency_contact'] = emergencyContact ?? residentData?['emergency_contact'];
      beds[bedIndex]['address'] = address ?? residentData?['address'];
      beds[bedIndex]['pincode'] = pincode ?? residentData?['pincode'];
      beds[bedIndex]['aadhaar_number'] = aadhaarNumber ?? residentData?['aadhaar_number'];
      beds[bedIndex]['pan_number'] = panNumber ?? residentData?['pan_number'];
      beds[bedIndex]['rent'] = rent ?? residentData?['rent'] ?? 8000;
    } catch (_) {
      room['beds'] = beds.map((b) => Map<String, dynamic>.from(b as Map)).toList();
      room['beds'][bedIndex]['status'] = 'Occupied';
      room['beds'][bedIndex]['occupant'] = residentName;
    }

    final assignedBedName = room['beds'][bedIndex]['name']?.toString() ?? 'Bed A';
    if (onBedAssigned != null) {
      onBedAssigned(assignedBedName);
    }

    // Update central residents list (match by name or phone)
    final resIndex = residents.indexWhere((r) {
      final matchName = r['name']?.toString().trim().toLowerCase() == residentName.trim().toLowerCase();
      final matchPhone = phone != null && phone.isNotEmpty && r['phone']?.toString().trim() == phone.trim();
      return matchName || matchPhone;
    });

    final finalRent = rent ?? residentData?['rent'] ?? 8000;
    final finalDueDate = dueDate ?? '05 Nov 2026';

    final wasPending = pendingResidents.any((p) {
      final matchName = p['name']?.toString().trim().toLowerCase() == residentName.trim().toLowerCase();
      final matchPhone = phone != null && phone.isNotEmpty && p['phone']?.toString().trim() == phone.trim();
      return matchName || matchPhone;
    });

    if (resIndex != -1) {
      residents[resIndex]['room'] = room['number'].toString();
      residents[resIndex]['room_number'] = room['number'].toString();
      if (floor != null && floor.trim().isNotEmpty) {
        residents[resIndex]['floor'] = floor.trim();
      } else if (room['floor'] != null) {
        residents[resIndex]['floor'] = room['floor'];
      }
      residents[resIndex]['bed'] = assignedBedName;
      residents[resIndex]['status'] = 'Active';
      residents[resIndex]['kyc'] = 'Verified';
      residents[resIndex]['rent'] = finalRent;
      residents[resIndex]['deposit'] = deposit ?? residents[resIndex]['deposit'] ?? (finalRent * 2);
      residents[resIndex]['due_date'] = finalDueDate;
      residents[resIndex]['payment_due_date'] = finalDueDate;
      if (phone != null && phone.isNotEmpty) {
        residents[resIndex]['phone'] = phone;
      }
    } else if (wasPending) {
      residents.insert(0, {
        'name': residentName,
        'phone': phone ?? '9876543290',
        'room': room['number'].toString(),
        'room_number': room['number'].toString(),
        'floor': floor ?? room['floor'] ?? '1st Floor',
        'bed': assignedBedName,
        'rent': finalRent,
        'deposit': deposit ?? (finalRent * 2),
        'kyc': 'Verified',
        'status': 'Active',
        'due_date': finalDueDate,
        'payment_due_date': finalDueDate,
        'email': email ?? '${residentName.toLowerCase().replaceAll(' ', '.')}@example.com',
        'dob': dob ?? '12/04/1997',
        'gender': gender ?? 'Male',
        'occupation': occupation ?? 'Resident',
        'joining_date': 'Today',
        'role': 'Resident',
        'property_name': 'BNR Luxury PG',
      });
    }

    // Remove from pendingResidents
    pendingResidents.removeWhere((p) {
      final matchName = p['name']?.toString().trim().toLowerCase() == residentName.trim().toLowerCase();
      final matchPhone = phone != null && phone.isNotEmpty && p['phone']?.toString().trim() == phone.trim();
      return matchName || matchPhone;
    });

    // Remove from adminNotifications
    adminNotifications.removeWhere((n) {
      final matchName = n['resident_name']?.toString().trim().toLowerCase() == residentName.trim().toLowerCase();
      final matchPhone = phone != null && phone.isNotEmpty && n['resident_phone']?.toString().trim() == phone.trim();
      return matchName || matchPhone;
    });

    saveResidentsToStorage();
    saveRoomsToStorage();
    return null; // Success
  }

  // Rule 3: When Admin manually updates a bed from Rooms Screen
  static void manualBedStatusUpdate(int roomIndex, int bedIndex, String newStatus) {
    final room = rooms[roomIndex];
    var bedsList = room['beds'] as List;

    if (newStatus == 'Occupied') {
      String placeholderName = 'Resident (${room['number']}-${bedsList[bedIndex]['name']})';
      try {
        bedsList[bedIndex]['status'] = 'Occupied';
        bedsList[bedIndex]['occupant'] = placeholderName;
      } catch (_) {
        room['beds'] = bedsList.map((b) => Map<String, dynamic>.from(b as Map)).toList();
        room['beds'][bedIndex]['status'] = 'Occupied';
        room['beds'][bedIndex]['occupant'] = placeholderName;
      }
      
      if (!residents.any((r) => r['name'] == placeholderName)) {
        residents.add({
          'name': placeholderName,
          'phone': '987654${room['number']}$bedIndex',
          'room': room['number'],
          'bed': room['beds'][bedIndex]['name'],
          'rent': 8000,
          'deposit': 16000,
          'kyc': 'Pending',
          'status': 'Active',
          'email': 'resident${room['number']}@example.com',
        });
      }
    } else {
      String? previousOccupant = bedsList[bedIndex]['occupant'];
      try {
        bedsList[bedIndex]['status'] = newStatus;
        bedsList[bedIndex]['occupant'] = null;
      } catch (_) {
        room['beds'] = bedsList.map((b) => Map<String, dynamic>.from(b as Map)).toList();
        room['beds'][bedIndex]['status'] = newStatus;
        room['beds'][bedIndex]['occupant'] = null;
      }
      
      if (previousOccupant != null) {
        residents.removeWhere((r) => r['name'] == previousOccupant);
      }
    }
    saveResidentsToStorage();
  }

  // Rule 4: Free bed on resident checkout
  static void checkoutResident(String roomNumber, String residentName) {
    final roomIndex = rooms.indexWhere((r) => r['number'].toString().toLowerCase() == roomNumber.trim().toLowerCase());
    if (roomIndex != -1) {
      final beds = rooms[roomIndex]['beds'] as List;
      for (int i = 0; i < beds.length; i++) {
        if (beds[i]['occupant']?.toString().trim().toLowerCase() == residentName.trim().toLowerCase()) {
          try {
            beds[i]['status'] = 'Available';
            beds[i]['occupant'] = null;
          } catch (_) {
            rooms[roomIndex]['beds'] = beds.map((b) => Map<String, dynamic>.from(b as Map)).toList();
            rooms[roomIndex]['beds'][i]['status'] = 'Available';
            rooms[roomIndex]['beds'][i]['occupant'] = null;
          }
          break;
        }
      }
    }
    residents.removeWhere((r) => r['name'] == residentName && r['room'] == roomNumber);
    saveResidentsToStorage();
  }

  static String? transferResident(String residentName, String newRoomNumber) {
    final cleanName = residentName.trim();
    final cleanNewRoom = newRoomNumber.trim();

    // 1. Find current room & bed location
    int oldRoomIndex = -1;
    int oldBedIndex = -1;
    
    for (int i = 0; i < rooms.length; i++) {
      final beds = rooms[i]['beds'] as List;
      for (int j = 0; j < beds.length; j++) {
        if (beds[j]['occupant']?.toString().trim().toLowerCase() == cleanName.toLowerCase()) {
          oldRoomIndex = i;
          oldBedIndex = j;
          break;
        }
      }
      if (oldRoomIndex != -1) break;
    }

    // 2. Find the new room (case-insensitive & trimmed)
    final newRoomIndex = rooms.indexWhere(
      (r) => r['number'].toString().trim().toLowerCase() == cleanNewRoom.toLowerCase(),
    );
    if (newRoomIndex == -1) {
      final availableRoomList = rooms.map((r) => r['number']).join(', ');
      return "New room $cleanNewRoom does not exist. (Available rooms: $availableRoomList)";
    }

    if (oldRoomIndex != -1 && oldRoomIndex == newRoomIndex) {
      return "Resident is already in room $cleanNewRoom.";
    }

    // 3. Find an empty bed in the new room
    final newBeds = rooms[newRoomIndex]['beds'] as List;
    final newBedIndex = newBeds.indexWhere((b) => b['status'] == 'Available');
    if (newBedIndex == -1) return "Room $cleanNewRoom is completely full.";

    // 4. Perform atomic swap using safe setters (with type-safe fallback)
    if (oldRoomIndex != -1) {
      try {
        rooms[oldRoomIndex]['beds'][oldBedIndex]['status'] = 'Available';
        rooms[oldRoomIndex]['beds'][oldBedIndex]['occupant'] = null;
      } catch (_) {
        rooms[oldRoomIndex]['beds'] = (rooms[oldRoomIndex]['beds'] as List)
            .map((b) => Map<String, dynamic>.from(b as Map))
            .toList();
        rooms[oldRoomIndex]['beds'][oldBedIndex]['status'] = 'Available';
        rooms[oldRoomIndex]['beds'][oldBedIndex]['occupant'] = null;
      }
    }

    try {
      rooms[newRoomIndex]['beds'][newBedIndex]['status'] = 'Occupied';
      rooms[newRoomIndex]['beds'][newBedIndex]['occupant'] = cleanName;
    } catch (_) {
      rooms[newRoomIndex]['beds'] = (rooms[newRoomIndex]['beds'] as List)
          .map((b) => Map<String, dynamic>.from(b as Map))
          .toList();
      rooms[newRoomIndex]['beds'][newBedIndex]['status'] = 'Occupied';
      rooms[newRoomIndex]['beds'][newBedIndex]['occupant'] = cleanName;
    }

    // 5. Update central residents list
    final resIndex = residents.indexWhere(
      (r) => r['name'].toString().trim().toLowerCase() == cleanName.toLowerCase(),
    );
    if (resIndex != -1) {
      residents[resIndex]['room'] = rooms[newRoomIndex]['number'].toString();
      residents[resIndex]['bed'] = rooms[newRoomIndex]['beds'][newBedIndex]['name'];
    }
    saveResidentsToStorage();

    return null; // Success
  }
}

