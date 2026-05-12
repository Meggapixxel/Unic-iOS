import Foundation

extension String {

    // MARK: - Common
    static var loading:      String { String(localized: "loading") }
    static var ok:           String { String(localized: "ok") }
    static var close:        String { String(localized: "close") }
    static var cancel:       String { String(localized: "cancel") }
    static var done:         String { String(localized: "done") }
    static var save:         String { String(localized: "save") }
    static var delete:       String { String(localized: "delete") }
    static var error:        String { String(localized: "error") }
    static var reset:        String { String(localized: "reset") }
    static var no_data:      String { String(localized: "no_data") }
    static var retry:        String { String(localized: "retry") }
    static var never:        String { String(localized: "never") }
    static var see_all:      String { String(localized: "see_all") }
    static var filter_all:   String { String(localized: "filter_all") }
    static var sorting:      String { String(localized: "sorting") }
    static var category:     String { String(localized: "category") }
    static var call:         String { String(localized: "call") }
    static var website:      String { String(localized: "website") }
    static var location:     String { String(localized: "location") }
    static var status:       String { String(localized: "status") }
    static var city:         String { String(localized: "city") }
    static var discard:      String { String(localized: "discard") }

    // MARK: - Auth
    static var auth_no_access_title:       String { String(localized: "auth_no_access_title") }
    static var auth_no_access_body:        String { String(localized: "auth_no_access_body") }
    static var auth_login_title:           String { String(localized: "auth_login_title") }
    static var auth_email_placeholder:     String { String(localized: "auth_email_placeholder") }
    static var auth_password_placeholder:  String { String(localized: "auth_password_placeholder") }
    static var auth_login_button:          String { String(localized: "auth_login_button") }
    static var auth_error_user_not_found:  String { String(localized: "auth_error_user_not_found") }
    static var auth_error_wrong_password:  String { String(localized: "auth_error_wrong_password") }

    // MARK: - Errors
    static var history_load_error:  String { String(localized: "history_load_error") }
    static var save_error:          String { String(localized: "save_error") }
    static var error_fetch_stock:   String { String(localized: "error_fetch_stock") }
    static var error_fetch_prices:  String { String(localized: "error_fetch_prices") }
    static func error_network(_ detail: String) -> String { String(localized: "error_network \(detail)") }
    static func error_parsing(_ detail: String) -> String { String(localized: "error_parsing \(detail)") }
    static func error_api(_ msg: String)        -> String { String(localized: "error_api \(msg)") }
    static func error_http(_ code: Int)         -> String { String(localized: "error_http \(code)") }
    static var error_unauthorized:              String    { String(localized: "error_unauthorized") }

    // MARK: - Salon List
    static var search_salons:  String { String(localized: "search_salons") }
    static var stat_total:     String { String(localized: "stat_total") }
    static var stat_new:       String { String(localized: "stat_new") }
    static var stat_contacted: String { String(localized: "stat_contacted") }
    static var stat_clients:   String { String(localized: "stat_clients") }
    static var salon_statuses: String { String(localized: "salon_statuses") }
    static var sort_by_date:                String { String(localized: "sort_by_date") }
    static var filter_language:             String { String(localized: "filter_language") }
    static var filter_date_added:           String { String(localized: "filter_date_added") }
    static var filter_date_this_month:      String { String(localized: "filter_date_this_month") }
    static var filter_date_this_year:       String { String(localized: "filter_date_this_year") }

    // MARK: - Status (short)
    static var status_new:        String { String(localized: "status_new") }
    static var status_contacted:  String { String(localized: "status_contacted") }
    static var status_test_drive: String { String(localized: "status_test_drive") }
    static var status_demo:       String { String(localized: "status_demo") }
    static var demo_date_label:   String { String(localized: "demo_date_label") }
    static var status_ordered:    String { String(localized: "status_ordered") }
    static var status_other:      String { String(localized: "status_other") }

    // MARK: - Status (full)
    static var status_new_full:        String { String(localized: "status_new_full") }
    static var status_contacted_full:  String { String(localized: "status_contacted_full") }
    static var status_test_drive_full: String { String(localized: "status_test_drive_full") }
    static var status_demo_full:       String { String(localized: "status_demo_full") }
    static var status_ordered_full:    String { String(localized: "status_ordered_full") }
    static var status_other_full:      String { String(localized: "status_other_full") }

    // MARK: - Status (descriptions)
    static var status_new_desc:        String { String(localized: "status_new_desc") }
    static var status_contacted_desc:  String { String(localized: "status_contacted_desc") }
    static var status_test_drive_desc: String { String(localized: "status_test_drive_desc") }
    static var status_demo_desc:       String { String(localized: "status_demo_desc") }
    static var status_ordered_desc:    String { String(localized: "status_ordered_desc") }
    static var status_other_desc:      String { String(localized: "status_other_desc") }

    // MARK: - Status (actions)
    static var status_new_action:        String { String(localized: "status_new_action") }
    static var status_contacted_action:  String { String(localized: "status_contacted_action") }
    static var status_test_drive_action: String { String(localized: "status_test_drive_action") }
    static var status_demo_action:       String { String(localized: "status_demo_action") }
    static var status_ordered_action:    String { String(localized: "status_ordered_action") }
    static var status_other_action:      String { String(localized: "status_other_action") }

    // MARK: - Sort
    static var sort_by_name:      String { String(localized: "sort_by_name") }
    static var sort_by_lead_temp: String { String(localized: "sort_by_lead_temp") }
    static var sort_by_status:    String { String(localized: "sort_by_status") }

    // MARK: - Salon Detail
    static var edit_note:          String { String(localized: "edit_note") }
    static var status_update_hint: String { String(localized: "status_update_hint") }
    static var copy_number:        String { String(localized: "copy_number") }
    static var current_status:     String { String(localized: "current_status") }
    static var change_history:     String { String(localized: "change_history") }
    static var lead_temp_label:    String { String(localized: "lead_temp_label") }
    static var enrichment:         String { String(localized: "enrichment") }
    static var delete_salon:       String { String(localized: "delete_salon") }
    static var delete_salon_question: String { String(localized: "delete_salon_question") }
    static var new_status:         String { String(localized: "new_status") }
    static var status_picker:      String { String(localized: "status_picker") }
    static var note_optional:      String { String(localized: "note_optional") }
    static var add_comment:        String { String(localized: "add_comment") }
    static var add_status:         String { String(localized: "add_status") }
    static var no_history:         String { String(localized: "no_history") }
    static var history_empty:      String { String(localized: "history_empty") }
    static var status_history:     String { String(localized: "status_history") }
    static func delete_confirmation(_ name: String) -> String {
        String(format: String(localized: "delete_confirmation %@"), name)
    }

    // MARK: - Add / Edit Salon
    static var add_salon:             String { String(localized: "add_salon") }
    static var edit_salon:            String { String(localized: "edit_salon") }
    static var section_main:          String { String(localized: "section_main") }
    static var section_contacts:      String { String(localized: "section_contacts") }
    static var section_notes:         String { String(localized: "section_notes") }
    static var salon_name_placeholder: String { String(localized: "salon_name_placeholder") }
    static var address_hint:          String { String(localized: "address_hint") }
    static var address_label:         String { String(localized: "address_label") }
    static var phone_label:           String { String(localized: "phone_label") }
    static var notes_placeholder:     String { String(localized: "notes_placeholder") }
    static var works_on_label:        String { String(localized: "works_on_label") }
    static var articles_label:        String { String(localized: "articles_label") }
    static var articles_search:       String { String(localized: "articles_search") }
    static var works_on_search:       String { String(localized: "works_on_search") }
    static var works_on_placeholder:  String { String(localized: "works_on_placeholder") }
    static var language_label:        String { String(localized: "language_label") }

    // MARK: - Salon Category
    static var salon_category_label:              String { String(localized: "salon_category_label") }
    static var salon_category_info_title:         String { String(localized: "salon_category_info_title") }
    static var salon_category_intro:              String { String(localized: "salon_category_intro") }
    static var salon_category_a_desc:             String { String(localized: "salon_category_a_desc") }
    static var salon_category_b_desc:             String { String(localized: "salon_category_b_desc") }
    static var salon_category_c_desc:             String { String(localized: "salon_category_c_desc") }
    static var salon_category_criteria_header:    String { String(localized: "salon_category_criteria_header") }
    static var salon_category_criteria_aesthetics: String { String(localized: "salon_category_criteria_aesthetics") }
    static var salon_category_criteria_seats:     String { String(localized: "salon_category_criteria_seats") }
    static var salon_category_criteria_equipment: String { String(localized: "salon_category_criteria_equipment") }
    static var salon_category_criteria_location:  String { String(localized: "salon_category_criteria_location") }
    static var salon_category_criteria_services:  String { String(localized: "salon_category_criteria_services") }
    static var salon_category_a: String { String(localized: "salon_category_a") }
    static var salon_category_b: String { String(localized: "salon_category_b") }
    static var salon_category_c: String { String(localized: "salon_category_c") }

    // MARK: - Lead Temp
    static var lead_temp_a:      String { String(localized: "lead_temp_a") }
    static var lead_temp_b:      String { String(localized: "lead_temp_b") }
    static var lead_temp_c:      String { String(localized: "lead_temp_c") }
    static var lead_temp_a_desc: String { String(localized: "lead_temp_a_desc") }
    static var lead_temp_b_desc: String { String(localized: "lead_temp_b_desc") }
    static var lead_temp_c_desc: String { String(localized: "lead_temp_c_desc") }
    static var lead_temp_intro:  String { String(localized: "lead_temp_intro") }
    static var scoring_header:        String { String(localized: "scoring_header") }
    static var scoring_website:       String { String(localized: "scoring_website") }
    static var scoring_phone:         String { String(localized: "scoring_phone") }
    static var scoring_google_maps:   String { String(localized: "scoring_google_maps") }
    static var scoring_coloring:      String { String(localized: "scoring_coloring") }
    static var scoring_extensions:    String { String(localized: "scoring_extensions") }
    static var scoring_barbershop:    String { String(localized: "scoring_barbershop") }
    static var scoring_kids:          String { String(localized: "scoring_kids") }
    static var scoring_thresholds:    String { String(localized: "scoring_thresholds") }

    // MARK: - Map
    static var no_coordinates:   String { String(localized: "no_coordinates") }
    static var no_location_data: String { String(localized: "no_location_data") }
    static var map_standard:     String { String(localized: "map_standard") }
    static var map_satellite:    String { String(localized: "map_satellite") }
    static var map_hybrid:       String { String(localized: "map_hybrid") }

    // MARK: - Route Planner
    static var route_planner:          String { String(localized: "route_planner") }
    static var route_select_salons:    String { String(localized: "route_select_salons") }
    static var route_select_all:       String { String(localized: "route_select_all") }
    static var route_deselect_all:     String { String(localized: "route_deselect_all") }
    static var route_build:            String { String(localized: "route_build") }
    static var route_driving:          String { String(localized: "route_driving") }
    static var route_walking:          String { String(localized: "route_walking") }
    static var route_distance:         String { String(localized: "route_distance") }
    static var route_time:             String { String(localized: "route_time") }
    static var route_stops:            String { String(localized: "route_stops") }
    static var route_navigate:         String { String(localized: "route_navigate") }
    static var route_transport:        String { String(localized: "route_transport") }
    static var route_error:            String { String(localized: "route_error") }
    static var route_not_enough_salons: String { String(localized: "route_not_enough_salons") }
    static var route_no_salons:        String { String(localized: "route_no_salons") }
    static var route_no_salons_desc:   String { String(localized: "route_no_salons_desc") }

    // MARK: - Discard
    static var discard_changes: String { String(localized: "discard_changes") }

    // MARK: - Test Drive
    static var test_drive:       String { String(localized: "test_drive") }
    static var test_drive_empty: String { String(localized: "test_drive_empty") }

    // MARK: - Notifications
    static var notif_disabled_title:  String { String(localized: "notif_disabled_title") }
    static var notif_disabled_body:   String { String(localized: "notif_disabled_body") }
    static var notif_disabled_action: String { String(localized: "notif_disabled_action") }
    static var notif_testdrive_soon_title:     String { String(localized: "notif_testdrive_soon_title") }
    static var notif_testdrive_deadline_title: String { String(localized: "notif_testdrive_deadline_title") }
    static func notif_testdrive_soon_body(_ name: String) -> String {
        String(format: String(localized: "notif_testdrive_soon_body"), name)
    }
    static func notif_testdrive_deadline_body(_ name: String) -> String {
        String(format: String(localized: "notif_testdrive_deadline_body"), name)
    }

    // MARK: - Created by
    static var created_by_label: String { String(localized: "created_by_label") }

    // MARK: - Salon model
    static var unnamed_salon: String { String(localized: "unnamed_salon") }

    // MARK: - FlexiBee / Barcode
    static var barcode_title:     String { String(localized: "barcode_title") }
    static var barcode_hint:      String { String(localized: "barcode_hint") }
    static var barcode_no_camera: String { String(localized: "barcode_no_camera") }
    static var barcode_searching: String { String(localized: "barcode_searching") }
    static var stock_nav_title:   String { String(localized: "stock_nav_title") }
    static var stock_no_data:     String { String(localized: "stock_no_data") }
    static var search_stock:      String { String(localized: "search_stock") }
    static func barcode_not_found(_ value: String) -> String {
        String(format: String(localized: "barcode_not_found %@"), value)
    }
    static func barcode_search_error(_ detail: String) -> String {
        String(format: String(localized: "barcode_search_error %@"), detail)
    }

    // MARK: - FlexiBee / Product Detail
    static var product_code:           String { String(localized: "product_code") }
    static var product_in_stock:       String { String(localized: "product_in_stock") }
    static var product_sell_price:     String { String(localized: "product_sell_price") }
    static var product_purchase_price: String { String(localized: "product_purchase_price") }
    static var product_margin:         String { String(localized: "product_margin") }
    static var copy_article:           String { String(localized: "copy_article") }
    static var copy_name:              String { String(localized: "copy_name") }
    static var copy_article_and_name:  String { String(localized: "copy_article_and_name") }

    // MARK: - FlexiBee (stock stats)
    static var stock_units: String { String(localized: "stock_units") }
    static var stock_low:   String { String(localized: "stock_low") }

    // MARK: - Sales
    static var sales_nav_title:             String { String(localized: "sales_nav_title") }
    static var sales_analytics:             String { String(localized: "sales_analytics") }
    static var sales_invoices:              String { String(localized: "sales_invoices") }
    static var sales_kpi_revenue:           String { String(localized: "sales_kpi_revenue") }
    static var sales_kpi_paid:              String { String(localized: "sales_kpi_paid") }
    static var sales_kpi_unpaid:            String { String(localized: "sales_kpi_unpaid") }
    static var sales_kpi_overdue:           String { String(localized: "sales_kpi_overdue") }
    static var sales_chart_monthly_revenue: String { String(localized: "sales_chart_monthly_revenue") }
    static var sales_chart_month:           String { String(localized: "sales_chart_month") }
    static var sales_chart_revenue:         String { String(localized: "sales_chart_revenue") }
    static var sales_top_clients:       String { String(localized: "sales_top_clients") }
    static var sales_top_products:      String { String(localized: "sales_top_products") }
    static var sales_search_prompt:         String { String(localized: "sales_search_prompt") }
    static var sales_invoices_empty:        String { String(localized: "sales_invoices_empty") }
    static func sales_quantity(_ n: Int)  -> String { String(localized: "sales_quantity \(n)") }

    // MARK: - Sales Period
    static var period_month: String { String(localized: "period_month") }
    static var period_year:  String { String(localized: "period_year") }

    // MARK: - Payment Status
    static var payment_paid:    String { String(localized: "payment_paid") }
    static var payment_partial: String { String(localized: "payment_partial") }
    static var payment_unpaid:  String { String(localized: "payment_unpaid") }
    static var payment_overdue: String { String(localized: "payment_overdue") }

    static var payment_method:        String { String(localized: "payment_method") }
    static var payment_method_prevod:  String { String(localized: "payment_method_prevod") }
    static var payment_method_hotove:  String { String(localized: "payment_method_hotove") }
    static var payment_method_karta:   String { String(localized: "payment_method_karta") }

    // MARK: - Create / Edit Invoice
    static var create_invoice_title:            String { String(localized: "create_invoice_title") }
    static var edit_invoice_title:              String { String(localized: "edit_invoice_title") }
    static var create_invoice_submit:           String { String(localized: "create_invoice_submit") }
    static var edit_invoice_action:             String { String(localized: "edit_invoice_action") }
    static var create_invoice_client:           String { String(localized: "create_invoice_client") }
    static var create_invoice_client_placeholder: String { String(localized: "create_invoice_client_placeholder") }
    static var create_invoice_client_search:    String { String(localized: "create_invoice_client_search") }
    static var create_invoice_dates:            String { String(localized: "create_invoice_dates") }
    static var create_invoice_issue_date:       String { String(localized: "create_invoice_issue_date") }
    static var create_invoice_due_date:         String { String(localized: "create_invoice_due_date") }
    static var create_invoice_items:            String { String(localized: "create_invoice_items") }
    static var create_invoice_add_item:            String { String(localized: "create_invoice_add_item") }
    static var create_invoice_add_item_from_stock: String { String(localized: "create_invoice_add_item_from_stock") }
    static var create_invoice_add_item_scan:       String { String(localized: "create_invoice_add_item_scan") }
    static var create_invoice_add_item_manual:     String { String(localized: "create_invoice_add_item_manual") }
    static var create_invoice_item_name:        String { String(localized: "create_invoice_item_name") }
    static var create_invoice_item_qty:         String { String(localized: "create_invoice_item_qty") }
    static var create_invoice_item_price:       String { String(localized: "create_invoice_item_price") }
    static var create_invoice_notes:            String { String(localized: "create_invoice_notes") }
    static var create_invoice_notes_placeholder: String { String(localized: "create_invoice_notes_placeholder") }
    static var create_invoice_pick_product:     String { String(localized: "create_invoice_pick_product") }
    static var new_client:                      String { String(localized: "new_client") }
    static var create_client_name_placeholder:  String { String(localized: "create_client_name_placeholder") }

    // MARK: - Stock Movement
    static var stock_movement_title:    String { String(localized: "stock_movement_title") }
    static var stock_movement_section:  String { String(localized: "stock_movement_section") }
    static var stock_movement_create:   String { String(localized: "stock_movement_create") }
    static var stock_movement_submit:   String { String(localized: "stock_movement_submit") }
    static var stock_movement_skip:     String { String(localized: "stock_movement_skip") }
    static var stock_movement_items:    String { String(localized: "stock_movement_items") }
    static var stock_movement_add_item: String { String(localized: "stock_movement_add_item") }
    static var stock_movement_code:     String { String(localized: "stock_movement_code") }
    static var stock_movement_edit:     String { String(localized: "stock_movement_edit") }
    static var stock_required_title:    String { String(localized: "stock_required_title") }
    static var stock_required_body:     String { String(localized: "stock_required_body") }

    // MARK: - Invoice Detail
    static var invoice_detail_items:    String { String(localized: "invoice_detail_items") }
    static var invoice_detail_no_items: String { String(localized: "invoice_detail_no_items") }
    static var pdf_documents:           String { String(localized: "pdf_documents") }
    static var pdf_invoice:             String { String(localized: "pdf_invoice") }
    static var pdf_cash_receipt:        String { String(localized: "pdf_cash_receipt") }
    static var invoice_status_change_title:  String { String(localized: "invoice_status_change_title") }
    static func invoice_status_change_to(_ s: String) -> String {
        String(format: String(localized: "invoice_status_change_to %@"), s)
    }
    static var delete_invoice_action:        String { String(localized: "delete_invoice_action") }
    static var delete_invoice_confirm_title: String { String(localized: "delete_invoice_confirm_title") }
    static func delete_invoice_confirm_body(_ number: String) -> String {
        String(format: String(localized: "delete_invoice_confirm_body %@"), number)
    }

    // MARK: - User Activity
    static var activity_statistics: String { String(localized: "activity_statistics") }
    static var activity_today:      String { String(localized: "activity_today") }
    static var activity_yesterday:  String { String(localized: "activity_yesterday") }
    static var activity_empty:      String { String(localized: "activity_empty") }
    static var activity_group_day:  String { String(localized: "activity_group_day") }
    static var activity_group_week: String { String(localized: "activity_group_week") }
    static var activity_this_week:  String { String(localized: "activity_this_week") }
    static var activity_last_week:  String { String(localized: "activity_last_week") }

    // MARK: - Users
    static var users_nav_title: String { String(localized: "users_nav_title") }
    static var users_empty:     String { String(localized: "users_empty") }
    static var role_admin:      String { String(localized: "role_admin") }
    static var role_manager:    String { String(localized: "role_manager") }
    static var role_sales:      String { String(localized: "role_sales") }

    // MARK: - Profile
    static var profile_nav_title:       String { String(localized: "profile_nav_title") }
    static var profile_logout:          String { String(localized: "profile_logout") }
    static var profile_logout_confirm:  String { String(localized: "profile_logout_confirm") }
    static var profile_activity:        String { String(localized: "profile_activity") }
    static var profile_activity_history:String { String(localized: "profile_activity_history") }

    // MARK: - Utilities

    var nilIfEmpty: String? { isEmpty ? nil : self }
}
