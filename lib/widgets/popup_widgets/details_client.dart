import 'dart:io';
import 'package:flutter/material.dart';

import '../../services/client_service.dart';
import 'details_edit_sheet.dart';
import '../../models/client_record.dart';

class EventDetailsClient extends StatefulWidget {
  final ClientRecord client;

  const EventDetailsClient({super.key, required this.client});

  @override
  State<EventDetailsClient> createState() => _EventDetailsClientState();
}

class _EventDetailsClientState extends State<EventDetailsClient> {
  bool _isEditing = false;
  final Map<String, String?> _errors = {};

  late final TextEditingController _businessNameController;
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _emailController;

  List<ClientRecord> _allClients = [];
  List<ClientRecord> _selectedClients = [];

  final _userService = ClientService();

  @override
  void initState() {
    super.initState();
    final c = widget.client;

    _nameController = TextEditingController(text: c.name);
    _businessNameController = TextEditingController(text: c.businessName);
    _addressController = TextEditingController(text: c.address);
    _emailController = TextEditingController(text: c.email);
    _phoneController = TextEditingController(text: c.phone);

    _loadClients();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _businessNameController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadClients() async {
    _userService.clientsStream().listen((clients) {
      if (!mounted) return;
      setState(() {
        _allClients = clients;
        _selectedClients = clients
            .where((c) => widget.client.name.contains(c.name))
            .toList();
      });
    });
  }

  void _cancelEdit() {
    final c = widget.client;
    setState(() {
      _isEditing = false;
      _nameController.text = c.name;
      _businessNameController.text = c.businessName;
      _addressController.text = c.address;
      _emailController.text = c.email;
      _phoneController.text = c.phone;
      _selectedClients = _allClients
          .where((c) => c.id.contains(c.id))
          .toList();
    });
  }

  Future<void> _save() async {
    setState(() {
      _errors['businessName'] = _businessNameController.text
          .trim()
          .isEmpty
          ? "BusinessName is required"
          : null;
      _errors['address'] = _addressController.text
          .trim()
          .isEmpty
          ? "Please select an address"
          : null;
      _errors['email'] = _emailController.text
          .trim()
          .isEmpty
          ? "Please select an email"
          : null;
      _errors['name'] = _nameController.text
          .trim()
          .isEmpty
          ? "Please select a name"
          : null;
      _errors['phone'] = _phoneController.text
          .trim()
          .isEmpty
          ? "Please insert a phone number"
          : null;
      _errors['clients'] = _selectedClients.isEmpty
          ? "Please select at least one client"
          : null;
    });

    if (_errors.values.any((c) => c != null)) return;

    if (_selectedClients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select at least one client")),
      );
      return;
    }

    final updated = ClientRecord(id: widget.client.id,
        businessName: _businessNameController.text.trim(),
        name: _nameController.text.trim(),
        address: _addressController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        contacts: );

    @override
    Widget build(BuildContext context) {
      return DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (BuildContext sheetContext,
            ScrollController scrollController) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => FocusScope.of(sheetContext).unfocus(),
            child: Container(
              decoration: BoxDecoration(
                color: Theme
                    .of(sheetContext)
                    .colorScheme
                    .surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 16,
                  bottom: MediaQuery
                      .of(sheetContext)
                      .viewInsets
                      .bottom + 60,
                ),
              ),
            ),
          );
        },
      );
    }
  }
