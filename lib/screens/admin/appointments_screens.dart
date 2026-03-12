import 'package:flutter/material.dart';

import '../../models/appointment_record.dart';
import '../../utils/colors.dart';
import '../../widgets/admin_drawers.dart';

class AdminAppointmentsPage extends StatefulWidget {
  const AdminAppointmentsPage({super.key});

  @override
  State<AdminAppointmentsPage> createState() => _AdminAppointmentsPageState();
}

class _AdminAppointmentsPageState extends State<AdminAppointmentsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AppointmentRecord> get _filteredAppointments {
    if (_query.trim().isEmpty) {
      return kAppointments;
    }

    final q = _query.toLowerCase().trim();
    return kAppointments.where((appointment) {
      return appointment.title.toLowerCase().contains(q) ||
          appointment.clientName.toLowerCase().contains(q) ||
          appointment.clientPhone.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final appointments = _filteredAppointments;

    return Scaffold(
      backgroundColor: Colors.white,
      endDrawer: AdminMenuDrawer(),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Column(
            children: [
              SizedBox(height: 10),
              Row(
                children: [
                  Spacer(),
                  Text(
                    'Appointments',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Spacer(),
                  Builder(
                    builder: (context) => GestureDetector(
                      onTap: () => Scaffold.of(context).openEndDrawer(),
                      child: Icon(Icons.menu, size: 28, color: Colors.black87),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Search by name or phone number...',
                  hintStyle: TextStyle(fontSize: 12, color: Colors.black38),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Color(0xFFDCDCDC)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: kPurple),
                  ),
                ),
              ),
              SizedBox(height: 14),
              Expanded(
                child: ListView.separated(
                  itemCount: appointments.length,
                  separatorBuilder: (_, _) => SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final appointment = appointments[index];
                    return _AppointmentCard(
                      appointment: appointment,
                      onTap: () => showAppointmentInfoPopup(
                        context,
                        appointment: appointment,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------- APPOINTMENTS DARK ---------------- */

class AdminAppointmentsDarkPage extends StatefulWidget {
  const AdminAppointmentsDarkPage({super.key});

  @override
  State<AdminAppointmentsDarkPage> createState() => _AdminAppointmentsDarkPageState();
}

class _AdminAppointmentsDarkPageState extends State<AdminAppointmentsDarkPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AppointmentRecord> get _filteredAppointments {
    if (_query.trim().isEmpty) {
      return kAppointments;
    }

    final q = _query.toLowerCase().trim();
    return kAppointments.where((appointment) {
      return appointment.title.toLowerCase().contains(q) ||
          appointment.clientName.toLowerCase().contains(q) ||
          appointment.clientPhone.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final appointments = _filteredAppointments;

    return Scaffold(
      backgroundColor: Colors.black,
      endDrawer: AdminMenuDrawerDark(),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Column(
            children: [
              SizedBox(height: 10),
              Row(
                children: [
                  Spacer(),
                  Text(
                    'Appointments',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Spacer(),
                  Builder(
                    builder: (context) => GestureDetector(
                      onTap: () => Scaffold.of(context).openEndDrawer(),
                      child: Icon(Icons.menu, size: 28, color: Colors.white),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              TextField(
                controller: _searchController,
                style: TextStyle(color: Colors.white),
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Search by name or phone number...',
                  hintStyle: TextStyle(fontSize: 12, color: Colors.white38),
                  filled: true,
                  fillColor: Color(0xFF171717),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Color(0xFF2A2A2A)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: kPurple),
                  ),
                ),
              ),
              SizedBox(height: 14),
              Expanded(
                child: ListView.separated(
                  itemCount: appointments.length,
                  separatorBuilder: (_, _) => SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final appointment = appointments[index];
                    return _AppointmentCardDark(
                      appointment: appointment,
                      onTap: () => showAppointmentInfoDarkPopup(
                        context,
                        appointment: appointment,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({
    required this.appointment,
    required this.onTap,
  });

  final AppointmentRecord appointment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Color(0xFFDCD4F8),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appointment.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '${appointment.clientName} (${appointment.clientPhone})',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 12),
              Text(
                appointment.date,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppointmentCardDark extends StatelessWidget {
  const _AppointmentCardDark({
    required this.appointment,
    required this.onTap,
  });

  final AppointmentRecord appointment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Color(0xFF171717),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Color(0xFF2A2A2A)),
          ),
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 10,
                height: 44,
                decoration: BoxDecoration(
                  color: Color(0xFFDCD4F8),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appointment.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '${appointment.clientName} (${appointment.clientPhone})',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 12),
              Text(
                appointment.date,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white60,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _appointmentInfoField({
  required String value,
  required String hintText,
  IconData? icon,
}) {
  return TextField(
    controller: TextEditingController(text: value),
    readOnly: true,
    decoration: InputDecoration(
      hintText: hintText,
      suffixIcon: icon != null ? Icon(icon, size: 18, color: Colors.black45) : null,
      filled: true,
      fillColor: Colors.white,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Color(0xFFD8D8D8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Color(0xFFD8D8D8)),
      ),
    ),
  );
}

Widget _appointmentInfoFieldDark({
  required String value,
  required String hintText,
  IconData? icon,
}) {
  return TextField(
    controller: TextEditingController(text: value),
    readOnly: true,
    style: TextStyle(color: Colors.white),
    decoration: InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: Colors.white38),
      suffixIcon: icon != null ? Icon(icon, size: 18, color: Colors.white54) : null,
      filled: true,
      fillColor: Color(0xFF171717),
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Color(0xFF2D2D2D)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Color(0xFF2D2D2D)),
      ),
    ),
  );
}

Future<void> showAppointmentInfoPopup(
    BuildContext context, {
      required AppointmentRecord appointment,
    }) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return FractionallySizedBox(
        heightFactor: 0.9,
        child: Container(
          padding: EdgeInsets.fromLTRB(18, 12, 18, 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              SizedBox(
                width: 44,
                child: Divider(thickness: 4, color: Color(0xFFD0D0D0)),
              ),
              SizedBox(height: 12),
              Text(
                'Event',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 18),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _appointmentInfoField(
                        value: appointment.title,
                        hintText: 'Event name',
                      ),
                      SizedBox(height: 12),
                      _appointmentInfoField(
                        value: appointment.date,
                        hintText: 'Date',
                        icon: Icons.calendar_today_outlined,
                      ),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _appointmentInfoField(
                              value: appointment.startTime,
                              hintText: 'Start Time',
                              icon: Icons.access_time,
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: _appointmentInfoField(
                              value: appointment.endTime,
                              hintText: 'End Time',
                              icon: Icons.access_time,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      _appointmentInfoField(
                        value: '${appointment.clientName} (${appointment.clientPhone})',
                        hintText: 'Client name (phone number)',
                      ),
                      SizedBox(height: 12),
                      _appointmentInfoField(
                        value: appointment.address,
                        hintText: 'Address',
                      ),
                      SizedBox(height: 12),
                      _appointmentInfoField(
                        value: appointment.jobType,
                        hintText: 'Type of job',
                      ),
                      SizedBox(height: 12),
                      _appointmentInfoField(
                        value: appointment.notes,
                        hintText: 'Notes',
                        icon: Icons.description_outlined,
                      ),
                      SizedBox(height: 12),
                      _appointmentInfoField(
                        value: appointment.materialsNeeded,
                        hintText: 'Materials needed',
                        icon: Icons.build_outlined,
                      ),
                      SizedBox(height: 12),
                      _appointmentInfoField(
                        value: appointment.pictures,
                        hintText: 'Pictures',
                        icon: Icons.image_outlined,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> showAppointmentInfoDarkPopup(
    BuildContext context, {
      required AppointmentRecord appointment,
    }) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return FractionallySizedBox(
        heightFactor: 0.9,
        child: Container(
          padding: EdgeInsets.fromLTRB(18, 12, 18, 22),
          decoration: BoxDecoration(
            color: Color(0xFF121212),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              SizedBox(
                width: 44,
                child: Divider(thickness: 4, color: Color(0xFF3A3A3A)),
              ),
              SizedBox(height: 12),
              Text(
                'Event',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 18),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _appointmentInfoFieldDark(
                        value: appointment.title,
                        hintText: 'Event name',
                      ),
                      SizedBox(height: 12),
                      _appointmentInfoFieldDark(
                        value: appointment.date,
                        hintText: 'Date',
                        icon: Icons.calendar_today_outlined,
                      ),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _appointmentInfoFieldDark(
                              value: appointment.startTime,
                              hintText: 'Start Time',
                              icon: Icons.access_time,
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: _appointmentInfoFieldDark(
                              value: appointment.endTime,
                              hintText: 'End Time',
                              icon: Icons.access_time,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      _appointmentInfoFieldDark(
                        value: '${appointment.clientName} (${appointment.clientPhone})',
                        hintText: 'Client name (phone number)',
                      ),
                      SizedBox(height: 12),
                      _appointmentInfoFieldDark(
                        value: appointment.address,
                        hintText: 'Address',
                      ),
                      SizedBox(height: 12),
                      _appointmentInfoFieldDark(
                        value: appointment.jobType,
                        hintText: 'Type of job',
                      ),
                      SizedBox(height: 12),
                      _appointmentInfoFieldDark(
                        value: appointment.notes,
                        hintText: 'Notes',
                        icon: Icons.description_outlined,
                      ),
                      SizedBox(height: 12),
                      _appointmentInfoFieldDark(
                        value: appointment.materialsNeeded,
                        hintText: 'Materials needed',
                        icon: Icons.build_outlined,
                      ),
                      SizedBox(height: 12),
                      _appointmentInfoFieldDark(
                        value: appointment.pictures,
                        hintText: 'Pictures',
                        icon: Icons.image_outlined,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
