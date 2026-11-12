import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AppData {
  // Central list to hold self-registered residents awaiting approval
  static List<Map<String, dynamic>> pendingResidents = [
    {'name': 'Rohan Mehta', 'phone': '9876543290', 'status': 'Pending Approval'},
  ];

  // Central complaints list
  static List<Map<String, dynamic>> complaints = [
    {
      'id': 'TKT-105',
      'issue': 'Air conditioner remote not responding and making rattling sound',
      'category': 'Appliance',
      'priority': 'High',
      'status': 'In Progress',
      'date': 'Yesterday, 4:30 PM',
    },
    {
      'id': 'TKT-102',
      'issue': 'Wi-Fi connection latency in Room 101 during night hours',
      'category': 'Wi-Fi/Internet',
      'priority': 'Medium',
      'status': 'Resolved',
      'date': '24 Oct 2026',
    },
  ];

  // Central mock admin notifications list
  static List<Map<String, dynamic>> adminNotifications = [
    {
      'id': 'notif_1',
      'title': 'New Resident Registration',
      'message': 'Rohan Mehta has self-registered and is waiting for room assignment.',
      'time': '10 mins ago',
      'resident_phone': '9876543290',
      'resident_name': 'Rohan Mehta',
      'document_type': 'Passport',
      'status': 'Pending',
      'timestamp': '2026-10-27T21:00:00.000Z',
    },
  ];

  // Pre-filled verified & pending residents matching Admin App
  static List<Map<String, dynamic>> residents = [
    {
      'name': 'Rohan Mehta',
      'phone': '9876543290',
      'room_number': null,
      'room': null,
      'bed': null,
      'rent': 0,
      'deposit': 0,
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
    },
    {
      'name': 'Siddarth Mishra',
      'phone': '9876543211',
      'room_number': '101',
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
      'document_type': 'Aadhaar',
      'document_image_url': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=400',
      'selfie_url': 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=400',
    },
    {
      'name': 'Pradeep Kumar',
      'phone': '9876543212',
      'room_number': '201',
      'room': '201',
      'bed': 'Bed A',
      'rent': 8000,
      'deposit': 8000,
      'kyc': 'Pending',
      'status': 'Active',
      'email': 'pradeep.k@example.com',
      'dob': '10/11/1997',
      'gender': 'Male',
      'occupation': 'Data Analyst',
      'emergency_contact': '9876543297',
      'address': 'Flat 101, Lakeview Apts, HSR Layout, Bengaluru',
      'pincode': '560102',
      'document_type': 'PAN',
      'document_image_url': 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=400',
      'selfie_url': 'https://images.unsplash.com/photo-1522075469751-3a6694fb2f61?w=400',
    },
    {
      'name': 'David Joseph',
      'phone': '9876543213',
      'room_number': '301',
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
      'document_type': 'Passport',
      'document_image_url': 'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=400',
      'selfie_url': 'https://images.unsplash.com/photo-1492562080023-ab3db95bfbce?w=400',
    },
    {
      'name': 'Anna Ben',
      'phone': '9876543214',
      'room_number': '102',
      'room': '102',
      'bed': 'Bed A',
      'rent': 7000,
      'deposit': 14000,
      'kyc': 'Rejected',
      'status': 'Checking Out',
      'email': 'anna.ben@example.com',
      'dob': '19/09/1999',
      'gender': 'Female',
      'occupation': 'UI/UX Designer',
      'emergency_contact': '9876543295',
      'address': 'House 88, BTM 2nd Stage, Bengaluru',
      'pincode': '560076',
      'document_type': 'Aadhaar',
      'document_image_url': 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=400',
      'selfie_url': 'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=400',
    },
  ];

  // Active logged-in resident session (defaults to verified active resident)
  static Map<String, dynamic> currentResident = residents[1];

  // Weekly Food Menu (Monday to Sunday)
  static List<Map<String, dynamic>> notices = [];
  static List<Map<String, dynamic>> foodMenu = [
    {'day': 'Monday', 'breakfast': 'Poha & Tea', 'lunch': 'Dal, Rice, Roti, Sabzi', 'dinner': 'Paneer, Roti, Rice'},
    {'day': 'Tuesday', 'breakfast': 'Idli & Sambar', 'lunch': 'Rajma, Rice, Roti', 'dinner': 'Mix Veg, Roti, Rice'},
    {'day': 'Wednesday', 'breakfast': 'Aloo Paratha & Curd', 'lunch': 'Kadhi Pakoda, Rice, Roti', 'dinner': 'Aloo Gobi, Dal, Rice'},
    {'day': 'Thursday', 'breakfast': 'Upma & Chutney', 'lunch': 'Chole, Rice, Bhature/Roti', 'dinner': 'Egg Curry / Kofta, Rice'},
    {'day': 'Friday', 'breakfast': 'Puri Bhaji', 'lunch': 'Sambhar, Rice, Papad, Curd', 'dinner': 'Veg Biryani & Raita'},
    {'day': 'Saturday', 'breakfast': 'Dosa & Sambar', 'lunch': 'Dal Tadka, Jeera Rice, Roti', 'dinner': 'Special Thali / Paneer Butter Masala'},
    {'day': 'Sunday', 'breakfast': 'Chole Kulche / Halwa', 'lunch': 'Dum Biryani, Salan, Raita', 'dinner': 'Khichdi / Light Meal & Dessert'},
  ];

  // Load data from browser memory with automatic sanitization and healing
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
            
            // Clean up any old demo resident named Rahul who has no bed in rooms & beds
            if (name.toLowerCase().contains('rahul')) {
              continue;
            }

            // Sync room_number and room
            if (map['room_number'] == null && map['room'] != null) {
              map['room_number'] = map['room'];
            } else if (map['room'] == null && map['room_number'] != null) {
              map['room'] = map['room_number'];
            }

            // Ensure status field
            if (map['status'] == null) {
              map['status'] = map['room_number'] != null ? 'Active' : 'Pending';
            }

            loaded.add(map);
          }

          if (loaded.isNotEmpty) {
            residents = loaded;
            currentResident = loaded.firstWhere(
              (r) =>
                  r['room_number'] != null &&
                  (r['status']?.toString().toLowerCase() ?? '') != 'pending',
              orElse: () => loaded.first,
            );
          }
        }
      }
    } catch (_) {
      // Fallback is already initialized in memory
    }
  }

  // Register a brand new resident (Self-registration flow)
  static Future<void> registerResident(Map<String, dynamic> residentData) async {
    // Ensure status is Pending and room_number is null
    final newResident = {
      ...residentData,
      'status': 'Pending',
      'room_number': null,
      'room': null,
      'bed': null,
      'rent': 0,
      'deposit': 0,
      'kyc': 'Under Review',
    };

    // Remove any existing entry with same phone number
    residents.removeWhere((r) => r['phone'] == newResident['phone']);
    residents.insert(0, newResident);
    currentResident = newResident;

    // Create Admin notification
    final notification = {
      'id': 'notif_${DateTime.now().millisecondsSinceEpoch}',
      'title': 'New Resident Registration',
      'message': '${newResident['name']} has self-registered and is waiting for room assignment.',
      'time': 'Just now',
      'resident_phone': newResident['phone'],
      'resident_name': newResident['name'],
      'document_type': newResident['document_type'] ?? 'Aadhaar',
      'status': 'Pending',
      'timestamp': DateTime.now().toIso8601String(),
    };
    adminNotifications.insert(0, notification);

    await saveResidentsToStorage();
  }

  // Save data to browser memory
  static Future<void> saveResidentsToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('demo_residents', jsonEncode(residents));
      await prefs.setString('demo_admin_notifications', jsonEncode(adminNotifications));
    } catch (_) {}
  }

  // Save food menu to browser memory
  static Future<void> saveFoodMenuToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('demo_food_menu', jsonEncode(foodMenu));
    } catch (_) {}
  }

  // Central Properties List for Resident App
  static List<Map<String, dynamic>> properties = [
    {
      'id': 'p1',
      'name': 'BNR Luxury PG',
      'city': 'Bengaluru',
      'pincode': '560095',
      'address': 'Koramangala 6th Block, Bengaluru',
      'full_address': '#124, 5th Cross, 6th Block, Near Sony World Signal, Koramangala, Bengaluru, Karnataka - 560095',
      'propertyType': 'PG',
      'type': 'Co-Living',
      'occupancyType': 'Co-Living',
      'floors': 4,
      'rooms': 45,
      'beds': 140,
      'status': 'Active',
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
      'full_address': 'Sector 2, 14th Main, HSR Layout, Bengaluru, Karnataka - 560102',
      'propertyType': 'PG',
      'type': 'Girls',
      'occupancyType': 'Girls',
      'floors': 3,
      'rooms': 30,
      'beds': 90,
      'status': 'Active',
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
      'full_address': 'Sector 2, 27th Main Rd, HSR Layout, Bengaluru, Karnataka - 560102',
      'propertyType': 'PG',
      'type': 'Boys',
      'occupancyType': 'Boys',
      'floors': 3,
      'rooms': 10,
      'beds': 18,
      'status': 'Active',
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
  ];

  static Map<String, dynamic> getPropertyByName(String? name) {
    if (name == null || name.isEmpty) return properties.first;
    return properties.firstWhere(
      (p) => p['name'].toString().toLowerCase().contains(name.toLowerCase()) ||
             name.toLowerCase().contains(p['name'].toString().toLowerCase()),
      orElse: () => properties.first,
    );
  }
}
