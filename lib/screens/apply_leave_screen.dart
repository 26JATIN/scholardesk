import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class ApplyLeaveScreen extends StatefulWidget {
  final Map<String, dynamic> clientDetails;
  final Map<String, dynamic> userData;

  const ApplyLeaveScreen({
    super.key,
    required this.clientDetails,
    required this.userData,
  });

  @override
  State<ApplyLeaveScreen> createState() => _ApplyLeaveScreenState();
}

class _ApplyLeaveScreenState extends State<ApplyLeaveScreen> {
  final ApiService _apiService = ApiService();
  final _formKey = GlobalKey<FormState>();
  
  // Form controllers
  final TextEditingController _eventNameController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  
  // Form values
  String _leaveType = '1'; // 1 = Duty Leave, 2 = Medical Leave
  String? _selectedCategory;
  DateTime? _startDate;
  DateTime? _endDate;
  String _timeSlot = '1'; // 1 = Full Day, 2 = Period Wise
  List<String> _selectedPeriods = [];
  List<Map<String, dynamic>> _attachedFiles = []; // List of {file: File, uploadedName: String, localName: String, size: int}
  
  // Data
  List<Map<String, dynamic>> _categories = [];
  
  // Loading states
  bool _isLoadingCategories = true;
  bool _isSubmitting = false;
  bool _isUploadingFile = false;

  @override
  void initState() {
    super.initState();
    _fetchCategories();
  }

  @override
  void dispose() {
    _eventNameController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _fetchCategories() async {
    try {
      debugPrint('🔄 Fetching leave categories...');
      await _apiService.ensureCookiesLoaded();
      
      final baseUrl = widget.clientDetails['baseUrl'];
      final clientAbbr = widget.clientDetails['client_abbr'];
      final sessionId = widget.userData['sessionId']?.toString() ?? '18';
      final userId = widget.userData['userId']?.toString() ?? '15260';
      
      debugPrint('📡 Categories API Request:');
      debugPrint('  BaseURL: $baseUrl');
      debugPrint('  Client: $clientAbbr');
      debugPrint('  UserID: $userId');
      debugPrint('  SessionID: $sessionId');
      
      final categories = await _apiService.getLeaveCategories(
        baseUrl: baseUrl,
        clientAbbr: clientAbbr,
        userId: userId,
        sessionId: sessionId,
      );

      debugPrint('✅ Fetched ${categories.length} categories');

      if (mounted) {
        setState(() {
          _categories = categories;
          if (_categories.isNotEmpty) {
            _selectedCategory = _categories[0]['dutyLeaveId']?.toString();
            debugPrint('📋 Selected default category: $_selectedCategory');
          }
          _isLoadingCategories = false;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error fetching categories: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        setState(() => _isLoadingCategories = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load categories: ${e.toString()}'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _submitLeave() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Validate based on leave type
    if (_leaveType == '1') {
      // Duty Leave validation
      if (_selectedCategory == null) {
        _showError('Please select a category');
        return;
      }
      if (_eventNameController.text.trim().isEmpty) {
        _showError('Please enter event name');
        return;
      }
    } else if (_leaveType == '2') {
      // Medical Leave validation - requires attachment (will implement later)
    }
    
    if (_startDate == null || _endDate == null) {
      _showError('Please select start and end dates');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      debugPrint('📤 Submitting leave application...');
      await _apiService.ensureCookiesLoaded();
      
      final baseUrl = widget.clientDetails['baseUrl'];
      final clientAbbr = widget.clientDetails['client_abbr'];
      final sessionId = widget.userData['sessionId']?.toString() ?? '18';
      final userId = widget.userData['userId']?.toString() ?? '15260';
      final roleId = widget.userData['roleId']?.toString() ?? '4';
      
      // Get all uploaded filenames in full server format (fullname|shortname) separated by comma
      final allFileNames = _attachedFiles.map((f) => f['serverResponse'] as String).join(',');
      
      final result = await _apiService.submitLeaveApplication(
        baseUrl: baseUrl,
        clientAbbr: clientAbbr,
        userId: userId,
        sessionId: sessionId,
        roleId: roleId,
        leaveType: _leaveType,
        category: _selectedCategory ?? '',
        eventName: _eventNameController.text.trim(),
        startDate: DateFormat('yyyy-MM-dd').format(_startDate!),
        endDate: DateFormat('yyyy-MM-dd').format(_endDate!),
        timeSlot: _timeSlot,
        periods: _selectedPeriods.join(','),
        reason: _reasonController.text.trim(),
        fileName: allFileNames.isNotEmpty ? allFileNames : null,
      );

      debugPrint('✅ Leave submission result: $result');

      if (mounted) {
        setState(() => _isSubmitting = false);
        
        // Check for various response formats
        final bool isSuccess = result['status'] == true || 
                               result['success'] == true ||
                               (result['status'] is String && result['status'] == 'success') ||
                               (result.containsKey('error') && result['error'] == null);
        
        final String? errorMessage = result['error'] ?? result['message'];
        final String? successMessage = result['success'] ?? result['message'];
        
        if (!isSuccess && errorMessage != null && errorMessage.isNotEmpty) {
          _showError(errorMessage);
        } else if (isSuccess) {
          _showSuccess(successMessage ?? 'Leave application submitted successfully! ✓');
          _clearForm();
          
          // Go back to leave history after 1.5 seconds
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted) Navigator.pop(context, true); // Pass true to indicate success
          });
        } else {
          // Fallback for unexpected response format
          _showError('Unexpected response from server. Please check leave history.');
        }
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error submitting leave: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        setState(() => _isSubmitting = false);
        
        // Extract meaningful error message
        String errorMsg = 'Failed to submit leave application';
        if (e.toString().contains('Exception:')) {
          errorMsg = e.toString().replaceAll('Exception:', '').trim();
        }
        _showError(errorMsg);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _clearForm() {
    _eventNameController.clear();
    _reasonController.clear();
    setState(() {
      _leaveType = '1';
      _selectedCategory = _categories.isNotEmpty ? _categories[0]['dutyLeaveId']?.toString() : null;
      _startDate = null;
      _endDate = null;
      _timeSlot = '1';
      _selectedPeriods = [];
      _attachedFiles.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkSurfaceColor : AppTheme.surfaceColor,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkCardColor : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: isDark ? Colors.white : Colors.black87,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Apply Leave',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ),
      body: _isLoadingCategories
          ? const Center(child: CircularProgressIndicator.adaptive())
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLeaveTypeSelector(isDark),
                    const SizedBox(height: 20),
                    
                    if (_leaveType == '1') ...[
                      _buildCategoryDropdown(isDark),
                      const SizedBox(height: 20),
                      _buildEventNameField(isDark),
                      const SizedBox(height: 20),
                    ],
                    
                    _buildDateFields(isDark),
                    const SizedBox(height: 20),
                    if (_leaveType == '1') ...[
                      _buildTimeSlotDropdown(isDark),
                      const SizedBox(height: 20),
                    ],
                    
                    if (_leaveType == '2') ...[
                      _buildAttachmentSection(isDark),
                      const SizedBox(height: 20),
                    ],
                    
                    const SizedBox(height: 12),
                    _buildSubmitButton(isDark),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildLeaveTypeSelector(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Leave Type *',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCardColor : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: (isDark ? Colors.white : Colors.black).withOpacity(0.1),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildLeaveTypeOption('1', 'Duty Leave', Icons.work_outline_rounded, isDark),
              ),
              Container(
                width: 1,
                height: 40,
                color: (isDark ? Colors.white : Colors.black).withOpacity(0.1),
              ),
              Expanded(
                child: _buildLeaveTypeOption('2', 'Medical Leave', Icons.local_hospital_rounded, isDark),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLeaveTypeOption(String value, String label, IconData icon, bool isDark) {
    final isSelected = _leaveType == value;
    
    return InkWell(
      onTap: () => setState(() => _leaveType = value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? AppTheme.primaryColor : (isDark ? Colors.grey.shade600 : Colors.grey.shade400),
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? AppTheme.primaryColor : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryDropdown(bool isDark) {
    // Find selected category name
    final selectedCategoryName = _categories.firstWhere(
      (cat) => cat['dutyLeaveId']?.toString() == _selectedCategory,
      orElse: () => {},
    )['categoryName'] ?? 'Select category';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Category *',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _showCategoryBottomSheet(isDark),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCardColor : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (isDark ? Colors.white : Colors.black).withOpacity(0.1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    selectedCategoryName,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: _selectedCategory != null
                          ? (isDark ? Colors.white : Colors.black87)
                          : (isDark ? Colors.grey.shade600 : Colors.grey.shade400),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showCategoryBottomSheet(bool isDark) {
    final TextEditingController searchController = TextEditingController();
    List<Map<String, dynamic>> filteredCategories = List.from(_categories);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void filterCategories(String query) {
              setModalState(() {
                if (query.isEmpty) {
                  filteredCategories = List.from(_categories);
                } else {
                  filteredCategories = _categories.where((category) {
                    final categoryName = category['categoryName']?.toString().toLowerCase() ?? '';
                    return categoryName.contains(query.toLowerCase());
                  }).toList();
                }
              });
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCardColor : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: (isDark ? Colors.white : Colors.black).withOpacity(0.1),
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Drag handle
                        Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        // Title
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Select Category',
                                style: GoogleFonts.inter(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: Icon(
                                Icons.close_rounded,
                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Search bar
                        TextField(
                          controller: searchController,
                          autofocus: true,
                          onChanged: filterCategories,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search categories...',
                            hintStyle: GoogleFonts.inter(
                              fontSize: 14,
                              color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                            ),
                            suffixIcon: searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: Icon(
                                      Icons.clear_rounded,
                                      color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                                    ),
                                    onPressed: () {
                                      searchController.clear();
                                      filterCategories('');
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: isDark ? AppTheme.darkSurfaceColor : Colors.grey.shade50,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Categories list
                  Expanded(
                    child: filteredCategories.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off_rounded,
                                  size: 64,
                                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No categories found',
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: filteredCategories.length,
                            itemBuilder: (context, index) {
                              final category = filteredCategories[index];
                              final categoryId = category['dutyLeaveId']?.toString();
                              final categoryName = category['categoryName'] ?? '';
                              final isSelected = categoryId == _selectedCategory;

                              return InkWell(
                                onTap: () {
                                  setState(() => _selectedCategory = categoryId);
                                  Navigator.pop(context);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppTheme.primaryColor.withOpacity(0.1)
                                        : Colors.transparent,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          categoryName,
                                          style: GoogleFonts.inter(
                                            fontSize: 15,
                                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                            color: isSelected
                                                ? AppTheme.primaryColor
                                                : (isDark ? Colors.white : Colors.black87),
                                          ),
                                        ),
                                      ),
                                      if (isSelected)
                                        Icon(
                                          Icons.check_circle_rounded,
                                          color: AppTheme.primaryColor,
                                          size: 24,
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEventNameField(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Event Name *',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _eventNameController,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: isDark ? Colors.white : Colors.black87,
          ),
          decoration: InputDecoration(
            hintText: 'Enter event name',
            hintStyle: GoogleFonts.inter(
              fontSize: 14,
              color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            filled: true,
            fillColor: isDark ? AppTheme.darkCardColor : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: (isDark ? Colors.white : Colors.black).withOpacity(0.1),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: (isDark ? Colors.white : Colors.black).withOpacity(0.1),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReasonField(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Reason/Remarks *',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _reasonController,
          maxLines: 4,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: isDark ? Colors.white : Colors.black87,
          ),
          decoration: InputDecoration(
            hintText: 'Enter reason for leave',
            hintStyle: GoogleFonts.inter(
              fontSize: 14,
              color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
            ),
            contentPadding: const EdgeInsets.all(16),
            filled: true,
            fillColor: isDark ? AppTheme.darkCardColor : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: (isDark ? Colors.white : Colors.black).withOpacity(0.1),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: (isDark ? Colors.white : Colors.black).withOpacity(0.1),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateFields(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _buildDateField(
            'Start Date *',
            _startDate,
            (date) => setState(() => _startDate = date),
            isDark,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildDateField(
            'End Date *',
            _endDate,
            (date) => setState(() => _endDate = date),
            isDark,
            firstDate: _startDate,
          ),
        ),
      ],
    );
  }

  Widget _buildDateField(
    String label,
    DateTime? value,
    Function(DateTime) onChanged,
    bool isDark, {
    DateTime? firstDate,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: value ?? DateTime.now(),
              firstDate: firstDate ?? DateTime(2020), // Allow dates from 2020
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (date != null) onChanged(date);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCardColor : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (isDark ? Colors.white : Colors.black).withOpacity(0.1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    value != null ? DateFormat('dd MMM yyyy').format(value) : 'Select date',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: value != null
                          ? (isDark ? Colors.white : Colors.black87)
                          : (isDark ? Colors.grey.shade600 : Colors.grey.shade400),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.calendar_today_rounded,
                  size: 18,
                  color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeSlotDropdown(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Time Slot *',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _timeSlot,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            filled: true,
            fillColor: isDark ? AppTheme.darkCardColor : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: (isDark ? Colors.white : Colors.black).withOpacity(0.1),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: (isDark ? Colors.white : Colors.black).withOpacity(0.1),
              ),
            ),
          ),
          style: GoogleFonts.inter(
            fontSize: 14,
            color: isDark ? Colors.white : Colors.black87,
          ),
          dropdownColor: isDark ? AppTheme.darkCardColor : Colors.white,
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: '1', child: Text('Full Day')),
            DropdownMenuItem(value: '2', child: Text('Period Wise')),
          ],
          onChanged: (value) => setState(() => _timeSlot = value!),
        ),
      ],
    );
  }

  Widget _buildAttachmentSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Upload Attachment',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            if (_attachedFiles.isNotEmpty)
              Text(
                '${_attachedFiles.length} file(s) uploaded',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: Colors.green,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        
        // Upload button
        InkWell(
          onTap: _isUploadingFile ? null : _pickFile,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCardColor : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (isDark ? Colors.white : Colors.black).withOpacity(0.1),
                style: BorderStyle.solid,
              ),
            ),
            child: _isUploadingFile
                ? Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Uploading file...',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.orange,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.add_rounded,
                          color: AppTheme.primaryColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _attachedFiles.isEmpty ? 'Choose file to upload' : 'Add another file',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.cloud_upload_outlined,
                        color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                        size: 20,
                      ),
                    ],
                  ),
          ),
        ),
        
        // List of uploaded files
        if (_attachedFiles.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...List.generate(_attachedFiles.length, (index) {
            final fileData = _attachedFiles[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.green.withOpacity(0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        color: Colors.green,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fileData['localName'],
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${(fileData['size'] / 1024).toStringAsFixed(1)} KB • Uploaded',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _removeAttachment(index, fileData['uploadedName']),
                      icon: Icon(
                        Icons.close_rounded,
                        color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                        size: 18,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
        
        const SizedBox(height: 8),
        Text(
          'Supported formats: PDF, JPG, PNG (Max 5MB per file)',
          style: GoogleFonts.inter(
            fontSize: 11,
            color: isDark ? Colors.grey.shade600 : Colors.grey.shade500,
          ),
        ),
      ],
    );
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        
        // Check file size (5MB limit)
        int fileSizeInBytes = file.lengthSync();
        double fileSizeInMB = fileSizeInBytes / (1024 * 1024);
        
        if (fileSizeInMB > 5) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'File size exceeds 5MB limit',
                  style: GoogleFonts.inter(),
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        
        setState(() {
          _isUploadingFile = true;
        });
        
        // Upload immediately
        await _uploadAttachment(file);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingFile = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error picking file: $e',
              style: GoogleFonts.inter(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _uploadAttachment(File file) async {
    try {
      debugPrint('🔄 Starting file upload...');
      
      final baseUrl = widget.clientDetails['baseUrl'];
      final clientAbbr = widget.clientDetails['client_abbr'];
      final userId = widget.userData['userId']?.toString() ?? '15260';
      final sessionId = widget.userData['sessionId']?.toString() ?? '18';
      
      await _apiService.ensureCookiesLoaded();
      
      final result = await _apiService.uploadLeaveAttachment(
        baseUrl: baseUrl,
        clientAbbr: clientAbbr,
        userId: userId,
        sessionId: sessionId,
        filePath: file.path,
      );
      
      if (mounted) {
        final uploadedFileName = result['fileName'] ?? file.path.split('/').last;
        final fullServerResponse = result['fullName'] ?? uploadedFileName;
        final rawPipeSeparated = '${fullServerResponse}|${uploadedFileName}';
        
        setState(() {
          _isUploadingFile = false;
          _attachedFiles.add({
            'file': file,
            'uploadedName': uploadedFileName, // Short name for deletion
            'serverResponse': rawPipeSeparated, // Full format for leave submission
            'localName': file.path.split('/').last,
            'size': file.lengthSync(),
          });
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ File uploaded successfully',
              style: GoogleFonts.inter(),
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Upload failed: $e');
      if (mounted) {
        setState(() {
          _isUploadingFile = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to upload file: $e',
              style: GoogleFonts.inter(),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _removeAttachment(int index, String uploadedFileName) async {
    try {
      debugPrint('🗑️ Removing attachment at index $index: $uploadedFileName');
      
      final baseUrl = widget.clientDetails['baseUrl'];
      final clientAbbr = widget.clientDetails['client_abbr'];
      
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
      
      final success = await _apiService.removeLeaveAttachment(
        baseUrl: baseUrl,
        clientAbbr: clientAbbr,
        fileName: uploadedFileName,
      );
      
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        
        if (success) {
          setState(() {
            _attachedFiles.removeAt(index);
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ File removed successfully',
                style: GoogleFonts.inter(),
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to remove file from server',
                style: GoogleFonts.inter(),
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Remove failed: $e');
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error removing file: $e',
              style: GoogleFonts.inter(),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Widget _buildSubmitButton(bool isDark) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _isSubmitting ? null : _submitLeave,
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.primaryColor,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isSubmitting
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                'Apply Leave',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
