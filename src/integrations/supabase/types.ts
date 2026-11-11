export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  public: {
    Tables: {
      m_account_map: {
        Row: {
          account_id: number
          key: string
          updated_at: string
        }
        Insert: {
          account_id: number
          key: string
          updated_at?: string
        }
        Update: {
          account_id?: number
          key?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "m_account_map_account_id_fkey"
            columns: ["account_id"]
            referencedRelation: "m_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      m_accounts: {
        Row: {
          account_type: string
          code: string
          created_at: string
          created_by: string | null
          currency: string | null
          description: string | null
          id: number
          is_active: boolean
          is_control: boolean
          is_postable: boolean
          name: string
          parent_id: number | null
          subtype: string
          updated_at: string
        }
        Insert: {
          account_type: string
          code: string
          created_at?: string
          created_by?: string | null
          currency?: string | null
          description?: string | null
          id?: never
          is_active?: boolean
          is_control?: boolean
          is_postable?: boolean
          name: string
          parent_id?: number | null
          subtype: string
          updated_at?: string
        }
        Update: {
          account_type?: string
          code?: string
          created_at?: string
          created_by?: string | null
          currency?: string | null
          description?: string | null
          id?: never
          is_active?: boolean
          is_control?: boolean
          is_postable?: boolean
          name?: string
          parent_id?: number | null
          subtype?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "m_accounts_currency_fkey"
            columns: ["currency"]
            referencedRelation: "m_currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "m_accounts_parent_id_fkey"
            columns: ["parent_id"]
            referencedRelation: "m_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      m_asset_categories: {
        Row: {
          accum_account_id: number | null
          asset_account_id: number
          code: string
          created_at: string
          expense_account_id: number | null
          id: number
          is_active: boolean
          method: string
          name: string
          updated_at: string
          useful_life_months: number
        }
        Insert: {
          accum_account_id?: number | null
          asset_account_id: number
          code: string
          created_at?: string
          expense_account_id?: number | null
          id?: never
          is_active?: boolean
          method?: string
          name: string
          updated_at?: string
          useful_life_months?: number
        }
        Update: {
          accum_account_id?: number | null
          asset_account_id?: number
          code?: string
          created_at?: string
          expense_account_id?: number | null
          id?: never
          is_active?: boolean
          method?: string
          name?: string
          updated_at?: string
          useful_life_months?: number
        }
        Relationships: [
          {
            foreignKeyName: "m_asset_categories_accum_account_id_fkey"
            columns: ["accum_account_id"]
            referencedRelation: "m_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "m_asset_categories_asset_account_id_fkey"
            columns: ["asset_account_id"]
            referencedRelation: "m_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "m_asset_categories_expense_account_id_fkey"
            columns: ["expense_account_id"]
            referencedRelation: "m_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      m_bank_accounts: {
        Row: {
          account_holder: string | null
          account_no: string | null
          bank_name: string | null
          code: string
          created_at: string
          currency: string
          gl_account_id: number
          id: number
          is_active: boolean
          kind: string
          name: string
          updated_at: string
        }
        Insert: {
          account_holder?: string | null
          account_no?: string | null
          bank_name?: string | null
          code: string
          created_at?: string
          currency?: string
          gl_account_id: number
          id?: never
          is_active?: boolean
          kind?: string
          name: string
          updated_at?: string
        }
        Update: {
          account_holder?: string | null
          account_no?: string | null
          bank_name?: string | null
          code?: string
          created_at?: string
          currency?: string
          gl_account_id?: number
          id?: never
          is_active?: boolean
          kind?: string
          name?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "m_bank_accounts_currency_fkey"
            columns: ["currency"]
            referencedRelation: "m_currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "m_bank_accounts_gl_account_id_fkey"
            columns: ["gl_account_id"]
            referencedRelation: "m_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      m_cost_centers: {
        Row: {
          code: string
          created_at: string
          id: number
          is_active: boolean
          name: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          id?: never
          is_active?: boolean
          name: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          id?: never
          is_active?: boolean
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
      m_currencies: {
        Row: {
          code: string
          created_at: string
          is_active: boolean
          name: string
          symbol: string | null
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          is_active?: boolean
          name: string
          symbol?: string | null
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          is_active?: boolean
          name?: string
          symbol?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      m_features: {
        Row: {
          feature_key: string
          feature_name: string
          icon_name: string | null
          id: number
          path: string | null
        }
        Insert: {
          feature_key: string
          feature_name: string
          icon_name?: string | null
          id: number
          path?: string | null
        }
        Update: {
          feature_key?: string
          feature_name?: string
          icon_name?: string | null
          id?: number
          path?: string | null
        }
        Relationships: []
      }
      m_fiscal_years: {
        Row: {
          closed_at: string | null
          closed_by: string | null
          closing_journal_id: number | null
          created_at: string
          end_date: string
          id: number
          start_date: string
          status: string
          year: number
        }
        Insert: {
          closed_at?: string | null
          closed_by?: string | null
          closing_journal_id?: number | null
          created_at?: string
          end_date: string
          id?: never
          start_date: string
          status?: string
          year: number
        }
        Update: {
          closed_at?: string | null
          closed_by?: string | null
          closing_journal_id?: number | null
          created_at?: string
          end_date?: string
          id?: never
          start_date?: string
          status?: string
          year?: number
        }
        Relationships: [
          {
            foreignKeyName: "m_fiscal_years_closed_by_fkey"
            columns: ["closed_by"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "m_fiscal_years_closing_journal_id_fkey"
            columns: ["closing_journal_id"]
            referencedRelation: "t_journals"
            referencedColumns: ["id"]
          },
        ]
      }
      m_fx_rates: {
        Row: {
          created_at: string
          created_by: string | null
          currency: string
          id: number
          rate: number
          rate_date: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          currency: string
          id?: never
          rate: number
          rate_date: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          currency?: string
          id?: never
          rate?: number
          rate_date?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "m_fx_rates_currency_fkey"
            columns: ["currency"]
            referencedRelation: "m_currencies"
            referencedColumns: ["code"]
          },
        ]
      }
      m_items: {
        Row: {
          code: string
          cogs_account_id: number | null
          created_at: string
          expense_account_id: number | null
          id: number
          inventory_account_id: number | null
          is_active: boolean
          kind: string
          name: string
          purchase_price: number
          purchase_tax_id: number | null
          revenue_account_id: number | null
          sales_price: number
          sales_tax_id: number | null
          unit: string
          unit_cost: number
          updated_at: string
          wht_tax_id: number | null
        }
        Insert: {
          code: string
          cogs_account_id?: number | null
          created_at?: string
          expense_account_id?: number | null
          id?: never
          inventory_account_id?: number | null
          is_active?: boolean
          kind?: string
          name: string
          purchase_price?: number
          purchase_tax_id?: number | null
          revenue_account_id?: number | null
          sales_price?: number
          sales_tax_id?: number | null
          unit?: string
          unit_cost?: number
          updated_at?: string
          wht_tax_id?: number | null
        }
        Update: {
          code?: string
          cogs_account_id?: number | null
          created_at?: string
          expense_account_id?: number | null
          id?: never
          inventory_account_id?: number | null
          is_active?: boolean
          kind?: string
          name?: string
          purchase_price?: number
          purchase_tax_id?: number | null
          revenue_account_id?: number | null
          sales_price?: number
          sales_tax_id?: number | null
          unit?: string
          unit_cost?: number
          updated_at?: string
          wht_tax_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "m_items_cogs_account_id_fkey"
            columns: ["cogs_account_id"]
            referencedRelation: "m_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "m_items_expense_account_id_fkey"
            columns: ["expense_account_id"]
            referencedRelation: "m_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "m_items_inventory_account_id_fkey"
            columns: ["inventory_account_id"]
            referencedRelation: "m_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "m_items_purchase_tax_id_fkey"
            columns: ["purchase_tax_id"]
            referencedRelation: "m_taxes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "m_items_revenue_account_id_fkey"
            columns: ["revenue_account_id"]
            referencedRelation: "m_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "m_items_sales_tax_id_fkey"
            columns: ["sales_tax_id"]
            referencedRelation: "m_taxes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "m_items_wht_tax_id_fkey"
            columns: ["wht_tax_id"]
            referencedRelation: "m_taxes"
            referencedColumns: ["id"]
          },
        ]
      }
      m_partners: {
        Row: {
          address: string | null
          bank_account_name: string | null
          bank_account_no: string | null
          bank_name: string | null
          city: string | null
          code: string
          contact_person: string | null
          created_at: string
          created_by: string | null
          credit_limit: number
          currency: string
          email: string | null
          id: number
          is_active: boolean
          is_customer: boolean
          is_vendor: boolean
          name: string
          note: string | null
          npwp: string | null
          phone: string | null
          term_id: number | null
          updated_at: string
        }
        Insert: {
          address?: string | null
          bank_account_name?: string | null
          bank_account_no?: string | null
          bank_name?: string | null
          city?: string | null
          code: string
          contact_person?: string | null
          created_at?: string
          created_by?: string | null
          credit_limit?: number
          currency?: string
          email?: string | null
          id?: never
          is_active?: boolean
          is_customer?: boolean
          is_vendor?: boolean
          name: string
          note?: string | null
          npwp?: string | null
          phone?: string | null
          term_id?: number | null
          updated_at?: string
        }
        Update: {
          address?: string | null
          bank_account_name?: string | null
          bank_account_no?: string | null
          bank_name?: string | null
          city?: string | null
          code?: string
          contact_person?: string | null
          created_at?: string
          created_by?: string | null
          credit_limit?: number
          currency?: string
          email?: string | null
          id?: never
          is_active?: boolean
          is_customer?: boolean
          is_vendor?: boolean
          name?: string
          note?: string | null
          npwp?: string | null
          phone?: string | null
          term_id?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "m_partners_currency_fkey"
            columns: ["currency"]
            referencedRelation: "m_currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "m_partners_term_id_fkey"
            columns: ["term_id"]
            referencedRelation: "m_payment_terms"
            referencedColumns: ["id"]
          },
        ]
      }
      m_payment_terms: {
        Row: {
          code: string
          created_at: string
          days: number
          id: number
          is_active: boolean
          name: string
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          days?: number
          id?: never
          is_active?: boolean
          name: string
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          days?: number
          id?: never
          is_active?: boolean
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
      m_periods: {
        Row: {
          closed_at: string | null
          closed_by: string | null
          end_date: string
          fiscal_year_id: number
          id: number
          period_no: number
          start_date: string
          status: string
        }
        Insert: {
          closed_at?: string | null
          closed_by?: string | null
          end_date: string
          fiscal_year_id: number
          id?: never
          period_no: number
          start_date: string
          status?: string
        }
        Update: {
          closed_at?: string | null
          closed_by?: string | null
          end_date?: string
          fiscal_year_id?: number
          id?: never
          period_no?: number
          start_date?: string
          status?: string
        }
        Relationships: [
          {
            foreignKeyName: "m_periods_closed_by_fkey"
            columns: ["closed_by"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "m_periods_fiscal_year_id_fkey"
            columns: ["fiscal_year_id"]
            referencedRelation: "m_fiscal_years"
            referencedColumns: ["id"]
          },
        ]
      }
      m_projects: {
        Row: {
          code: string
          created_at: string
          end_date: string | null
          id: number
          is_active: boolean
          name: string
          partner_id: number | null
          start_date: string | null
          updated_at: string
        }
        Insert: {
          code: string
          created_at?: string
          end_date?: string | null
          id?: never
          is_active?: boolean
          name: string
          partner_id?: number | null
          start_date?: string | null
          updated_at?: string
        }
        Update: {
          code?: string
          created_at?: string
          end_date?: string | null
          id?: never
          is_active?: boolean
          name?: string
          partner_id?: number | null
          start_date?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "m_projects_partner_id_fkey"
            columns: ["partner_id"]
            referencedRelation: "m_partners"
            referencedColumns: ["id"]
          },
        ]
      }
      m_roles: {
        Row: {
          created_at: string
          id: number
          rank: number
          role_name: string
        }
        Insert: {
          created_at?: string
          id: number
          rank: number
          role_name: string
        }
        Update: {
          created_at?: string
          id?: number
          rank?: number
          role_name?: string
        }
        Relationships: []
      }
      m_settings: {
        Row: {
          address: string | null
          approval_threshold: number
          base_currency: string
          company_name: string
          created_at: string
          created_by: string | null
          demo_mode: boolean
          doc_prefixes: Json
          email: string | null
          id: number
          invoice_footer: string | null
          is_pkp: boolean
          legal_name: string | null
          logo_url: string | null
          npwp: string | null
          phone: string | null
          require_journal_approval: boolean
          timezone: string
          updated_at: string
        }
        Insert: {
          address?: string | null
          approval_threshold?: number
          base_currency?: string
          company_name?: string
          created_at?: string
          created_by?: string | null
          demo_mode?: boolean
          doc_prefixes?: Json
          email?: string | null
          id?: number
          invoice_footer?: string | null
          is_pkp?: boolean
          legal_name?: string | null
          logo_url?: string | null
          npwp?: string | null
          phone?: string | null
          require_journal_approval?: boolean
          timezone?: string
          updated_at?: string
        }
        Update: {
          address?: string | null
          approval_threshold?: number
          base_currency?: string
          company_name?: string
          created_at?: string
          created_by?: string | null
          demo_mode?: boolean
          doc_prefixes?: Json
          email?: string | null
          id?: number
          invoice_footer?: string | null
          is_pkp?: boolean
          legal_name?: string | null
          logo_url?: string | null
          npwp?: string | null
          phone?: string | null
          require_journal_approval?: boolean
          timezone?: string
          updated_at?: string
        }
        Relationships: []
      }
      m_taxes: {
        Row: {
          code: string
          created_at: string
          dpp_factor: number
          id: number
          is_active: boolean
          kind: string
          name: string
          purchase_account_id: number
          rate: number
          sales_account_id: number
          updated_at: string
          wht_type: string | null
        }
        Insert: {
          code: string
          created_at?: string
          dpp_factor?: number
          id?: never
          is_active?: boolean
          kind: string
          name: string
          purchase_account_id: number
          rate: number
          sales_account_id: number
          updated_at?: string
          wht_type?: string | null
        }
        Update: {
          code?: string
          created_at?: string
          dpp_factor?: number
          id?: never
          is_active?: boolean
          kind?: string
          name?: string
          purchase_account_id?: number
          rate?: number
          sales_account_id?: number
          updated_at?: string
          wht_type?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "m_taxes_purchase_account_id_fkey"
            columns: ["purchase_account_id"]
            referencedRelation: "m_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "m_taxes_sales_account_id_fkey"
            columns: ["sales_account_id"]
            referencedRelation: "m_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          avatar_url: string | null
          created_at: string
          created_by: string | null
          employee_code: string | null
          full_name: string | null
          id: string
          is_superadmin: boolean
          locale: string | null
          role_id: number | null
          updated_at: string
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string
          created_by?: string | null
          employee_code?: string | null
          full_name?: string | null
          id: string
          is_superadmin?: boolean
          locale?: string | null
          role_id?: number | null
          updated_at?: string
        }
        Update: {
          avatar_url?: string | null
          created_at?: string
          created_by?: string | null
          employee_code?: string | null
          full_name?: string | null
          id?: string
          is_superadmin?: boolean
          locale?: string | null
          role_id?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "profiles_role_id_fkey"
            columns: ["role_id"]
            referencedRelation: "m_roles"
            referencedColumns: ["id"]
          },
        ]
      }
      t_asset_depreciation: {
        Row: {
          amount: number
          asset_id: number
          created_at: string
          id: number
          journal_id: number
          period_id: number
        }
        Insert: {
          amount: number
          asset_id: number
          created_at?: string
          id?: never
          journal_id: number
          period_id: number
        }
        Update: {
          amount?: number
          asset_id?: number
          created_at?: string
          id?: never
          journal_id?: number
          period_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "t_asset_depreciation_asset_id_fkey"
            columns: ["asset_id"]
            referencedRelation: "t_assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_asset_depreciation_journal_id_fkey"
            columns: ["journal_id"]
            referencedRelation: "t_journals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_asset_depreciation_period_id_fkey"
            columns: ["period_id"]
            referencedRelation: "m_periods"
            referencedColumns: ["id"]
          },
        ]
      }
      t_assets: {
        Row: {
          accumulated_opening: number
          acquisition_date: string
          category_id: number
          code: string
          cost: number
          cost_center_id: number | null
          created_at: string
          created_by: string | null
          disposal_date: string | null
          disposal_journal_id: number | null
          disposal_proceeds: number | null
          id: number
          in_service_date: string
          location: string | null
          method: string
          name: string
          note: string | null
          salvage_value: number
          serial_no: string | null
          source_invoice_id: number | null
          status: string
          updated_at: string
          useful_life_months: number
        }
        Insert: {
          accumulated_opening?: number
          acquisition_date: string
          category_id: number
          code: string
          cost: number
          cost_center_id?: number | null
          created_at?: string
          created_by?: string | null
          disposal_date?: string | null
          disposal_journal_id?: number | null
          disposal_proceeds?: number | null
          id?: never
          in_service_date: string
          location?: string | null
          method: string
          name: string
          note?: string | null
          salvage_value?: number
          serial_no?: string | null
          source_invoice_id?: number | null
          status?: string
          updated_at?: string
          useful_life_months: number
        }
        Update: {
          accumulated_opening?: number
          acquisition_date?: string
          category_id?: number
          code?: string
          cost?: number
          cost_center_id?: number | null
          created_at?: string
          created_by?: string | null
          disposal_date?: string | null
          disposal_journal_id?: number | null
          disposal_proceeds?: number | null
          id?: never
          in_service_date?: string
          location?: string | null
          method?: string
          name?: string
          note?: string | null
          salvage_value?: number
          serial_no?: string | null
          source_invoice_id?: number | null
          status?: string
          updated_at?: string
          useful_life_months?: number
        }
        Relationships: [
          {
            foreignKeyName: "t_assets_category_id_fkey"
            columns: ["category_id"]
            referencedRelation: "m_asset_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_assets_cost_center_id_fkey"
            columns: ["cost_center_id"]
            referencedRelation: "m_cost_centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_assets_created_by_fkey"
            columns: ["created_by"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_assets_disposal_journal_id_fkey"
            columns: ["disposal_journal_id"]
            referencedRelation: "t_journals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_assets_source_invoice_id_fkey"
            columns: ["source_invoice_id"]
            referencedRelation: "t_invoices"
            referencedColumns: ["id"]
          },
        ]
      }
      t_audit_log: {
        Row: {
          action: string
          actor_id: string | null
          created_at: string
          detail: Json | null
          entity_id: string
          entity_type: string
          id: number
        }
        Insert: {
          action: string
          actor_id?: string | null
          created_at?: string
          detail?: Json | null
          entity_id: string
          entity_type: string
          id?: never
        }
        Update: {
          action?: string
          actor_id?: string | null
          created_at?: string
          detail?: Json | null
          entity_id?: string
          entity_type?: string
          id?: never
        }
        Relationships: [
          {
            foreignKeyName: "t_audit_log_actor_id_fkey"
            columns: ["actor_id"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      t_bank_statement_lines: {
        Row: {
          amount: number
          description: string | null
          id: number
          journal_line_id: number | null
          line_date: string
          matched_at: string | null
          matched_by: string | null
          reference: string | null
          statement_id: number
        }
        Insert: {
          amount: number
          description?: string | null
          id?: never
          journal_line_id?: number | null
          line_date: string
          matched_at?: string | null
          matched_by?: string | null
          reference?: string | null
          statement_id: number
        }
        Update: {
          amount?: number
          description?: string | null
          id?: never
          journal_line_id?: number | null
          line_date?: string
          matched_at?: string | null
          matched_by?: string | null
          reference?: string | null
          statement_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "t_bank_statement_lines_journal_line_id_fkey"
            columns: ["journal_line_id"]
            referencedRelation: "t_journal_lines"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_bank_statement_lines_matched_by_fkey"
            columns: ["matched_by"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_bank_statement_lines_statement_id_fkey"
            columns: ["statement_id"]
            referencedRelation: "t_bank_statements"
            referencedColumns: ["id"]
          },
        ]
      }
      t_bank_statements: {
        Row: {
          bank_account_id: number
          closing_balance: number
          created_at: string
          created_by: string | null
          finished_at: string | null
          finished_by: string | null
          id: number
          note: string | null
          opening_balance: number
          start_date: string
          statement_date: string
          status: string
          updated_at: string
        }
        Insert: {
          bank_account_id: number
          closing_balance?: number
          created_at?: string
          created_by?: string | null
          finished_at?: string | null
          finished_by?: string | null
          id?: never
          note?: string | null
          opening_balance?: number
          start_date: string
          statement_date: string
          status?: string
          updated_at?: string
        }
        Update: {
          bank_account_id?: number
          closing_balance?: number
          created_at?: string
          created_by?: string | null
          finished_at?: string | null
          finished_by?: string | null
          id?: never
          note?: string | null
          opening_balance?: number
          start_date?: string
          statement_date?: string
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "t_bank_statements_bank_account_id_fkey"
            columns: ["bank_account_id"]
            referencedRelation: "m_bank_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_bank_statements_created_by_fkey"
            columns: ["created_by"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_bank_statements_finished_by_fkey"
            columns: ["finished_by"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      t_bank_transfers: {
        Row: {
          created_at: string
          created_by: string | null
          doc_no: string | null
          fee_amount: number
          from_amount: number
          from_bank_id: number
          from_rate: number
          id: number
          journal_id: number | null
          note: string | null
          posted_at: string | null
          posted_by: string | null
          reference: string | null
          status: string
          to_amount: number
          to_bank_id: number
          to_rate: number
          transfer_date: string
          updated_at: string
          void_journal_id: number | null
          void_reason: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          doc_no?: string | null
          fee_amount?: number
          from_amount: number
          from_bank_id: number
          from_rate?: number
          id?: never
          journal_id?: number | null
          note?: string | null
          posted_at?: string | null
          posted_by?: string | null
          reference?: string | null
          status?: string
          to_amount: number
          to_bank_id: number
          to_rate?: number
          transfer_date?: string
          updated_at?: string
          void_journal_id?: number | null
          void_reason?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          doc_no?: string | null
          fee_amount?: number
          from_amount?: number
          from_bank_id?: number
          from_rate?: number
          id?: never
          journal_id?: number | null
          note?: string | null
          posted_at?: string | null
          posted_by?: string | null
          reference?: string | null
          status?: string
          to_amount?: number
          to_bank_id?: number
          to_rate?: number
          transfer_date?: string
          updated_at?: string
          void_journal_id?: number | null
          void_reason?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "t_bank_transfers_created_by_fkey"
            columns: ["created_by"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_bank_transfers_from_bank_id_fkey"
            columns: ["from_bank_id"]
            referencedRelation: "m_bank_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_bank_transfers_journal_id_fkey"
            columns: ["journal_id"]
            referencedRelation: "t_journals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_bank_transfers_posted_by_fkey"
            columns: ["posted_by"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_bank_transfers_to_bank_id_fkey"
            columns: ["to_bank_id"]
            referencedRelation: "m_bank_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_bank_transfers_void_journal_id_fkey"
            columns: ["void_journal_id"]
            referencedRelation: "t_journals"
            referencedColumns: ["id"]
          },
        ]
      }
      t_budget_lines: {
        Row: {
          account_id: number
          amount: number
          budget_id: number
          id: number
          period_no: number
        }
        Insert: {
          account_id: number
          amount?: number
          budget_id: number
          id?: never
          period_no: number
        }
        Update: {
          account_id?: number
          amount?: number
          budget_id?: number
          id?: never
          period_no?: number
        }
        Relationships: [
          {
            foreignKeyName: "t_budget_lines_account_id_fkey"
            columns: ["account_id"]
            referencedRelation: "m_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_budget_lines_budget_id_fkey"
            columns: ["budget_id"]
            referencedRelation: "t_budgets"
            referencedColumns: ["id"]
          },
        ]
      }
      t_budgets: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          cost_center_id: number | null
          created_at: string
          created_by: string | null
          fiscal_year_id: number
          id: number
          name: string
          note: string | null
          status: string
          updated_at: string
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          cost_center_id?: number | null
          created_at?: string
          created_by?: string | null
          fiscal_year_id: number
          id?: never
          name: string
          note?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          cost_center_id?: number | null
          created_at?: string
          created_by?: string | null
          fiscal_year_id?: number
          id?: never
          name?: string
          note?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "t_budgets_approved_by_fkey"
            columns: ["approved_by"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_budgets_cost_center_id_fkey"
            columns: ["cost_center_id"]
            referencedRelation: "m_cost_centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_budgets_created_by_fkey"
            columns: ["created_by"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_budgets_fiscal_year_id_fkey"
            columns: ["fiscal_year_id"]
            referencedRelation: "m_fiscal_years"
            referencedColumns: ["id"]
          },
        ]
      }
      t_cash_txn_lines: {
        Row: {
          account_id: number
          amount: number
          cost_center_id: number | null
          description: string | null
          id: number
          project_id: number | null
          tax_amount: number
          tax_base: number
          tax_id: number | null
          txn_id: number
        }
        Insert: {
          account_id: number
          amount: number
          cost_center_id?: number | null
          description?: string | null
          id?: never
          project_id?: number | null
          tax_amount?: number
          tax_base?: number
          tax_id?: number | null
          txn_id: number
        }
        Update: {
          account_id?: number
          amount?: number
          cost_center_id?: number | null
          description?: string | null
          id?: never
          project_id?: number | null
          tax_amount?: number
          tax_base?: number
          tax_id?: number | null
          txn_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "t_cash_txn_lines_account_id_fkey"
            columns: ["account_id"]
            referencedRelation: "m_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_cash_txn_lines_cost_center_id_fkey"
            columns: ["cost_center_id"]
            referencedRelation: "m_cost_centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_cash_txn_lines_project_id_fkey"
            columns: ["project_id"]
            referencedRelation: "m_projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_cash_txn_lines_tax_id_fkey"
            columns: ["tax_id"]
            referencedRelation: "m_taxes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_cash_txn_lines_txn_id_fkey"
            columns: ["txn_id"]
            referencedRelation: "t_cash_txns"
            referencedColumns: ["id"]
          },
        ]
      }
      t_cash_txns: {
        Row: {
          approved_by: string | null
          bank_account_id: number
          created_at: string
          created_by: string | null
          currency: string
          description: string | null
          direction: string
          doc_no: string | null
          fx_rate: number
          id: number
          journal_id: number | null
          partner_id: number | null
          payee: string | null
          posted_at: string | null
          posted_by: string | null
          reference: string | null
          reject_reason: string | null
          status: string
          submitted_at: string | null
          tax_invoice_date: string | null
          tax_invoice_no: string | null
          total: number
          txn_date: string
          updated_at: string
          void_journal_id: number | null
          void_reason: string | null
        }
        Insert: {
          approved_by?: string | null
          bank_account_id: number
          created_at?: string
          created_by?: string | null
          currency?: string
          description?: string | null
          direction: string
          doc_no?: string | null
          fx_rate?: number
          id?: never
          journal_id?: number | null
          partner_id?: number | null
          payee?: string | null
          posted_at?: string | null
          posted_by?: string | null
          reference?: string | null
          reject_reason?: string | null
          status?: string
          submitted_at?: string | null
          tax_invoice_date?: string | null
          tax_invoice_no?: string | null
          total?: number
          txn_date?: string
          updated_at?: string
          void_journal_id?: number | null
          void_reason?: string | null
        }
        Update: {
          approved_by?: string | null
          bank_account_id?: number
          created_at?: string
          created_by?: string | null
          currency?: string
          description?: string | null
          direction?: string
          doc_no?: string | null
          fx_rate?: number
          id?: never
          journal_id?: number | null
          partner_id?: number | null
          payee?: string | null
          posted_at?: string | null
          posted_by?: string | null
          reference?: string | null
          reject_reason?: string | null
          status?: string
          submitted_at?: string | null
          tax_invoice_date?: string | null
          tax_invoice_no?: string | null
          total?: number
          txn_date?: string
          updated_at?: string
          void_journal_id?: number | null
          void_reason?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "t_cash_txns_approved_by_fkey"
            columns: ["approved_by"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_cash_txns_bank_account_id_fkey"
            columns: ["bank_account_id"]
            referencedRelation: "m_bank_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_cash_txns_created_by_fkey"
            columns: ["created_by"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_cash_txns_currency_fkey"
            columns: ["currency"]
            referencedRelation: "m_currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "t_cash_txns_journal_id_fkey"
            columns: ["journal_id"]
            referencedRelation: "t_journals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_cash_txns_partner_id_fkey"
            columns: ["partner_id"]
            referencedRelation: "m_partners"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_cash_txns_posted_by_fkey"
            columns: ["posted_by"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_cash_txns_void_journal_id_fkey"
            columns: ["void_journal_id"]
            referencedRelation: "t_journals"
            referencedColumns: ["id"]
          },
        ]
      }
      t_doc_counters: {
        Row: {
          kind: string
          last_no: number
          period: string
        }
        Insert: {
          kind: string
          last_no: number
          period: string
        }
        Update: {
          kind?: string
          last_no?: number
          period?: string
        }
        Relationships: []
      }
      t_error_log: {
        Row: {
          context: Json | null
          created_at: string
          id: number
          message: string
          source: string
          user_id: string | null
        }
        Insert: {
          context?: Json | null
          created_at?: string
          id?: never
          message: string
          source: string
          user_id?: string | null
        }
        Update: {
          context?: Json | null
          created_at?: string
          id?: never
          message?: string
          source?: string
          user_id?: string | null
        }
        Relationships: []
      }
      t_expense_claim_lines: {
        Row: {
          account_id: number
          amount: number
          claim_id: number
          cost_center_id: number | null
          description: string
          expense_date: string
          id: number
          project_id: number | null
          receipt_path: string | null
        }
        Insert: {
          account_id: number
          amount: number
          claim_id: number
          cost_center_id?: number | null
          description: string
          expense_date: string
          id?: never
          project_id?: number | null
          receipt_path?: string | null
        }
        Update: {
          account_id?: number
          amount?: number
          claim_id?: number
          cost_center_id?: number | null
          description?: string
          expense_date?: string
          id?: never
          project_id?: number | null
          receipt_path?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "t_expense_claim_lines_account_id_fkey"
            columns: ["account_id"]
            referencedRelation: "m_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_expense_claim_lines_claim_id_fkey"
            columns: ["claim_id"]
            referencedRelation: "t_expense_claims"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_expense_claim_lines_cost_center_id_fkey"
            columns: ["cost_center_id"]
            referencedRelation: "m_cost_centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_expense_claim_lines_project_id_fkey"
            columns: ["project_id"]
            referencedRelation: "m_projects"
            referencedColumns: ["id"]
          },
        ]
      }
      t_expense_claims: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          claim_date: string
          created_at: string
          created_by: string | null
          doc_no: string | null
          employee_id: string
          id: number
          journal_id: number | null
          paid_at: string | null
          paid_from_bank_id: number | null
          payment_journal_id: number | null
          reject_reason: string | null
          status: string
          submitted_at: string | null
          title: string
          total: number
          updated_at: string
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          claim_date?: string
          created_at?: string
          created_by?: string | null
          doc_no?: string | null
          employee_id?: string
          id?: never
          journal_id?: number | null
          paid_at?: string | null
          paid_from_bank_id?: number | null
          payment_journal_id?: number | null
          reject_reason?: string | null
          status?: string
          submitted_at?: string | null
          title: string
          total?: number
          updated_at?: string
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          claim_date?: string
          created_at?: string
          created_by?: string | null
          doc_no?: string | null
          employee_id?: string
          id?: never
          journal_id?: number | null
          paid_at?: string | null
          paid_from_bank_id?: number | null
          payment_journal_id?: number | null
          reject_reason?: string | null
          status?: string
          submitted_at?: string | null
          title?: string
          total?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "t_expense_claims_approved_by_fkey"
            columns: ["approved_by"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_expense_claims_created_by_fkey"
            columns: ["created_by"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_expense_claims_employee_id_fkey"
            columns: ["employee_id"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_expense_claims_journal_id_fkey"
            columns: ["journal_id"]
            referencedRelation: "t_journals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_expense_claims_paid_from_bank_id_fkey"
            columns: ["paid_from_bank_id"]
            referencedRelation: "m_bank_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_expense_claims_payment_journal_id_fkey"
            columns: ["payment_journal_id"]
            referencedRelation: "t_journals"
            referencedColumns: ["id"]
          },
        ]
      }
      t_invoice_lines: {
        Row: {
          account_id: number | null
          cost_center_id: number | null
          description: string | null
          discount: number
          id: number
          invoice_id: number
          item_id: number | null
          line_no: number
          line_subtotal: number
          project_id: number | null
          qty: number
          tax_amount: number
          tax_base: number
          tax_id: number | null
          unit_price: number
          wht_amount: number
          wht_tax_id: number | null
        }
        Insert: {
          account_id?: number | null
          cost_center_id?: number | null
          description?: string | null
          discount?: number
          id?: never
          invoice_id: number
          item_id?: number | null
          line_no?: number
          line_subtotal?: number
          project_id?: number | null
          qty?: number
          tax_amount?: number
          tax_base?: number
          tax_id?: number | null
          unit_price?: number
          wht_amount?: number
          wht_tax_id?: number | null
        }
        Update: {
          account_id?: number | null
          cost_center_id?: number | null
          description?: string | null
          discount?: number
          id?: never
          invoice_id?: number
          item_id?: number | null
          line_no?: number
          line_subtotal?: number
          project_id?: number | null
          qty?: number
          tax_amount?: number
          tax_base?: number
          tax_id?: number | null
          unit_price?: number
          wht_amount?: number
          wht_tax_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "t_invoice_lines_account_id_fkey"
            columns: ["account_id"]
            referencedRelation: "m_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_invoice_lines_cost_center_id_fkey"
            columns: ["cost_center_id"]
            referencedRelation: "m_cost_centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_invoice_lines_invoice_id_fkey"
            columns: ["invoice_id"]
            referencedRelation: "t_invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_invoice_lines_item_id_fkey"
            columns: ["item_id"]
            referencedRelation: "m_items"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_invoice_lines_project_id_fkey"
            columns: ["project_id"]
            referencedRelation: "m_projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_invoice_lines_tax_id_fkey"
            columns: ["tax_id"]
            referencedRelation: "m_taxes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_invoice_lines_wht_tax_id_fkey"
            columns: ["wht_tax_id"]
            referencedRelation: "m_taxes"
            referencedColumns: ["id"]
          },
        ]
      }
      t_invoices: {
        Row: {
          approved_by: string | null
          attachment_path: string | null
          cost_center_id: number | null
          created_at: string
          created_by: string | null
          currency: string
          discount_total: number
          doc_no: string | null
          doc_type: string
          due_date: string | null
          fx_rate: number
          id: number
          invoice_date: string
          journal_id: number | null
          note: string | null
          original_invoice_id: number | null
          paid_amount: number
          partner_id: number
          posted_at: string | null
          posted_by: string | null
          project_id: number | null
          reference: string | null
          reject_reason: string | null
          status: string
          submitted_at: string | null
          subtotal: number
          tax_invoice_date: string | null
          tax_invoice_no: string | null
          tax_total: number
          term_id: number | null
          total: number
          updated_at: string
          void_journal_id: number | null
          void_reason: string | null
          wht_total: number
        }
        Insert: {
          approved_by?: string | null
          attachment_path?: string | null
          cost_center_id?: number | null
          created_at?: string
          created_by?: string | null
          currency?: string
          discount_total?: number
          doc_no?: string | null
          doc_type: string
          due_date?: string | null
          fx_rate?: number
          id?: never
          invoice_date?: string
          journal_id?: number | null
          note?: string | null
          original_invoice_id?: number | null
          paid_amount?: number
          partner_id: number
          posted_at?: string | null
          posted_by?: string | null
          project_id?: number | null
          reference?: string | null
          reject_reason?: string | null
          status?: string
          submitted_at?: string | null
          subtotal?: number
          tax_invoice_date?: string | null
          tax_invoice_no?: string | null
          tax_total?: number
          term_id?: number | null
          total?: number
          updated_at?: string
          void_journal_id?: number | null
          void_reason?: string | null
          wht_total?: number
        }
        Update: {
          approved_by?: string | null
          attachment_path?: string | null
          cost_center_id?: number | null
          created_at?: string
          created_by?: string | null
          currency?: string
          discount_total?: number
          doc_no?: string | null
          doc_type?: string
          due_date?: string | null
          fx_rate?: number
          id?: never
          invoice_date?: string
          journal_id?: number | null
          note?: string | null
          original_invoice_id?: number | null
          paid_amount?: number
          partner_id?: number
          posted_at?: string | null
          posted_by?: string | null
          project_id?: number | null
          reference?: string | null
          reject_reason?: string | null
          status?: string
          submitted_at?: string | null
          subtotal?: number
          tax_invoice_date?: string | null
          tax_invoice_no?: string | null
          tax_total?: number
          term_id?: number | null
          total?: number
          updated_at?: string
          void_journal_id?: number | null
          void_reason?: string | null
          wht_total?: number
        }
        Relationships: [
          {
            foreignKeyName: "t_invoices_approved_by_fkey"
            columns: ["approved_by"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_invoices_cost_center_id_fkey"
            columns: ["cost_center_id"]
            referencedRelation: "m_cost_centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_invoices_created_by_fkey"
            columns: ["created_by"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_invoices_currency_fkey"
            columns: ["currency"]
            referencedRelation: "m_currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "t_invoices_journal_id_fkey"
            columns: ["journal_id"]
            referencedRelation: "t_journals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_invoices_original_invoice_id_fkey"
            columns: ["original_invoice_id"]
            referencedRelation: "t_invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_invoices_partner_id_fkey"
            columns: ["partner_id"]
            referencedRelation: "m_partners"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_invoices_posted_by_fkey"
            columns: ["posted_by"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_invoices_project_id_fkey"
            columns: ["project_id"]
            referencedRelation: "m_projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_invoices_term_id_fkey"
            columns: ["term_id"]
            referencedRelation: "m_payment_terms"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_invoices_void_journal_id_fkey"
            columns: ["void_journal_id"]
            referencedRelation: "t_journals"
            referencedColumns: ["id"]
          },
        ]
      }
      t_journal_lines: {
        Row: {
          account_id: number
          cost_center_id: number | null
          created_at: string
          credit: number
          currency: string | null
          debit: number
          fc_amount: number | null
          id: number
          journal_id: number
          line_no: number
          memo: string | null
          partner_id: number | null
          project_id: number | null
        }
        Insert: {
          account_id: number
          cost_center_id?: number | null
          created_at?: string
          credit?: number
          currency?: string | null
          debit?: number
          fc_amount?: number | null
          id?: never
          journal_id: number
          line_no?: number
          memo?: string | null
          partner_id?: number | null
          project_id?: number | null
        }
        Update: {
          account_id?: number
          cost_center_id?: number | null
          created_at?: string
          credit?: number
          currency?: string | null
          debit?: number
          fc_amount?: number | null
          id?: never
          journal_id?: number
          line_no?: number
          memo?: string | null
          partner_id?: number | null
          project_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "t_journal_lines_account_id_fkey"
            columns: ["account_id"]
            referencedRelation: "m_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_journal_lines_cost_center_id_fkey"
            columns: ["cost_center_id"]
            referencedRelation: "m_cost_centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_journal_lines_currency_fkey"
            columns: ["currency"]
            referencedRelation: "m_currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "t_journal_lines_journal_id_fkey"
            columns: ["journal_id"]
            referencedRelation: "t_journals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_journal_lines_partner_id_fkey"
            columns: ["partner_id"]
            referencedRelation: "m_partners"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_journal_lines_project_id_fkey"
            columns: ["project_id"]
            referencedRelation: "m_projects"
            referencedColumns: ["id"]
          },
        ]
      }
      t_journals: {
        Row: {
          approved_by: string | null
          created_at: string
          created_by: string | null
          doc_no: string | null
          id: number
          journal_date: string
          kind: string
          memo: string | null
          period_id: number | null
          posted_at: string | null
          posted_by: string | null
          reference: string | null
          reject_reason: string | null
          reversal_of: number | null
          reversed_by: number | null
          source_id: number | null
          source_type: string | null
          status: string
          submitted_at: string | null
          total: number
          updated_at: string
        }
        Insert: {
          approved_by?: string | null
          created_at?: string
          created_by?: string | null
          doc_no?: string | null
          id?: never
          journal_date?: string
          kind?: string
          memo?: string | null
          period_id?: number | null
          posted_at?: string | null
          posted_by?: string | null
          reference?: string | null
          reject_reason?: string | null
          reversal_of?: number | null
          reversed_by?: number | null
          source_id?: number | null
          source_type?: string | null
          status?: string
          submitted_at?: string | null
          total?: number
          updated_at?: string
        }
        Update: {
          approved_by?: string | null
          created_at?: string
          created_by?: string | null
          doc_no?: string | null
          id?: never
          journal_date?: string
          kind?: string
          memo?: string | null
          period_id?: number | null
          posted_at?: string | null
          posted_by?: string | null
          reference?: string | null
          reject_reason?: string | null
          reversal_of?: number | null
          reversed_by?: number | null
          source_id?: number | null
          source_type?: string | null
          status?: string
          submitted_at?: string | null
          total?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "t_journals_approved_by_fkey"
            columns: ["approved_by"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_journals_created_by_fkey"
            columns: ["created_by"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_journals_period_id_fkey"
            columns: ["period_id"]
            referencedRelation: "m_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_journals_posted_by_fkey"
            columns: ["posted_by"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_journals_reversal_of_fkey"
            columns: ["reversal_of"]
            referencedRelation: "t_journals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_journals_reversed_by_fkey"
            columns: ["reversed_by"]
            referencedRelation: "t_journals"
            referencedColumns: ["id"]
          },
        ]
      }
      t_note_applications: {
        Row: {
          amount: number
          applied_date: string
          created_at: string
          created_by: string | null
          fx_journal_id: number | null
          id: number
          invoice_id: number
          note_id: number
        }
        Insert: {
          amount: number
          applied_date?: string
          created_at?: string
          created_by?: string | null
          fx_journal_id?: number | null
          id?: never
          invoice_id: number
          note_id: number
        }
        Update: {
          amount?: number
          applied_date?: string
          created_at?: string
          created_by?: string | null
          fx_journal_id?: number | null
          id?: never
          invoice_id?: number
          note_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "t_note_applications_created_by_fkey"
            columns: ["created_by"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_note_applications_fx_journal_id_fkey"
            columns: ["fx_journal_id"]
            referencedRelation: "t_journals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_note_applications_invoice_id_fkey"
            columns: ["invoice_id"]
            referencedRelation: "t_invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_note_applications_note_id_fkey"
            columns: ["note_id"]
            referencedRelation: "t_invoices"
            referencedColumns: ["id"]
          },
        ]
      }
      t_notifications: {
        Row: {
          body: string | null
          created_at: string
          created_by: string | null
          id: number
          is_read: boolean
          link: string | null
          title: string
          updated_at: string
          user_id: string
        }
        Insert: {
          body?: string | null
          created_at?: string
          created_by?: string | null
          id?: never
          is_read?: boolean
          link?: string | null
          title: string
          updated_at?: string
          user_id: string
        }
        Update: {
          body?: string | null
          created_at?: string
          created_by?: string | null
          id?: never
          is_read?: boolean
          link?: string | null
          title?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "t_notifications_user_id_fkey"
            columns: ["user_id"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      t_payment_allocations: {
        Row: {
          amount: number
          applied_date: string | null
          created_at: string
          fx_journal_id: number | null
          id: number
          invoice_id: number
          payment_id: number
          reclass_journal_id: number | null
        }
        Insert: {
          amount: number
          applied_date?: string | null
          created_at?: string
          fx_journal_id?: number | null
          id?: never
          invoice_id: number
          payment_id: number
          reclass_journal_id?: number | null
        }
        Update: {
          amount?: number
          applied_date?: string | null
          created_at?: string
          fx_journal_id?: number | null
          id?: never
          invoice_id?: number
          payment_id?: number
          reclass_journal_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "t_payment_allocations_fx_journal_id_fkey"
            columns: ["fx_journal_id"]
            referencedRelation: "t_journals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_payment_allocations_invoice_id_fkey"
            columns: ["invoice_id"]
            referencedRelation: "t_invoices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_payment_allocations_payment_id_fkey"
            columns: ["payment_id"]
            referencedRelation: "t_payments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_payment_allocations_reclass_journal_id_fkey"
            columns: ["reclass_journal_id"]
            referencedRelation: "t_journals"
            referencedColumns: ["id"]
          },
        ]
      }
      t_payments: {
        Row: {
          allocated_amount: number
          amount: number
          approved_by: string | null
          bank_account_id: number
          created_at: string
          created_by: string | null
          currency: string
          direction: string
          doc_no: string | null
          fx_rate: number
          id: number
          journal_id: number | null
          note: string | null
          partner_id: number
          payment_date: string
          posted_at: string | null
          posted_by: string | null
          reference: string | null
          reject_reason: string | null
          status: string
          submitted_at: string | null
          updated_at: string
          void_journal_id: number | null
          void_reason: string | null
          wht_amount: number
          wht_base: number | null
          wht_slip_no: string | null
          wht_tax_id: number | null
        }
        Insert: {
          allocated_amount?: number
          amount: number
          approved_by?: string | null
          bank_account_id: number
          created_at?: string
          created_by?: string | null
          currency?: string
          direction: string
          doc_no?: string | null
          fx_rate?: number
          id?: never
          journal_id?: number | null
          note?: string | null
          partner_id: number
          payment_date?: string
          posted_at?: string | null
          posted_by?: string | null
          reference?: string | null
          reject_reason?: string | null
          status?: string
          submitted_at?: string | null
          updated_at?: string
          void_journal_id?: number | null
          void_reason?: string | null
          wht_amount?: number
          wht_base?: number | null
          wht_slip_no?: string | null
          wht_tax_id?: number | null
        }
        Update: {
          allocated_amount?: number
          amount?: number
          approved_by?: string | null
          bank_account_id?: number
          created_at?: string
          created_by?: string | null
          currency?: string
          direction?: string
          doc_no?: string | null
          fx_rate?: number
          id?: never
          journal_id?: number | null
          note?: string | null
          partner_id?: number
          payment_date?: string
          posted_at?: string | null
          posted_by?: string | null
          reference?: string | null
          reject_reason?: string | null
          status?: string
          submitted_at?: string | null
          updated_at?: string
          void_journal_id?: number | null
          void_reason?: string | null
          wht_amount?: number
          wht_base?: number | null
          wht_slip_no?: string | null
          wht_tax_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "t_payments_approved_by_fkey"
            columns: ["approved_by"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_payments_bank_account_id_fkey"
            columns: ["bank_account_id"]
            referencedRelation: "m_bank_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_payments_created_by_fkey"
            columns: ["created_by"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_payments_currency_fkey"
            columns: ["currency"]
            referencedRelation: "m_currencies"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "t_payments_journal_id_fkey"
            columns: ["journal_id"]
            referencedRelation: "t_journals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_payments_partner_id_fkey"
            columns: ["partner_id"]
            referencedRelation: "m_partners"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_payments_posted_by_fkey"
            columns: ["posted_by"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_payments_void_journal_id_fkey"
            columns: ["void_journal_id"]
            referencedRelation: "t_journals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_payments_wht_tax_id_fkey"
            columns: ["wht_tax_id"]
            referencedRelation: "m_taxes"
            referencedColumns: ["id"]
          },
        ]
      }
      t_recurring_journal_lines: {
        Row: {
          account_id: number
          cost_center_id: number | null
          credit: number
          debit: number
          id: number
          memo: string | null
          project_id: number | null
          recurring_id: number
        }
        Insert: {
          account_id: number
          cost_center_id?: number | null
          credit?: number
          debit?: number
          id?: never
          memo?: string | null
          project_id?: number | null
          recurring_id: number
        }
        Update: {
          account_id?: number
          cost_center_id?: number | null
          credit?: number
          debit?: number
          id?: never
          memo?: string | null
          project_id?: number | null
          recurring_id?: number
        }
        Relationships: [
          {
            foreignKeyName: "t_recurring_journal_lines_account_id_fkey"
            columns: ["account_id"]
            referencedRelation: "m_accounts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_recurring_journal_lines_cost_center_id_fkey"
            columns: ["cost_center_id"]
            referencedRelation: "m_cost_centers"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_recurring_journal_lines_project_id_fkey"
            columns: ["project_id"]
            referencedRelation: "m_projects"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_recurring_journal_lines_recurring_id_fkey"
            columns: ["recurring_id"]
            referencedRelation: "t_recurring_journals"
            referencedColumns: ["id"]
          },
        ]
      }
      t_recurring_journals: {
        Row: {
          created_at: string
          created_by: string | null
          end_date: string | null
          frequency: string
          id: number
          is_active: boolean
          last_journal_id: number | null
          memo: string | null
          name: string
          next_run: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          end_date?: string | null
          frequency?: string
          id?: never
          is_active?: boolean
          last_journal_id?: number | null
          memo?: string | null
          name: string
          next_run: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          end_date?: string | null
          frequency?: string
          id?: never
          is_active?: boolean
          last_journal_id?: number | null
          memo?: string | null
          name?: string
          next_run?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "t_recurring_journals_created_by_fkey"
            columns: ["created_by"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_recurring_journals_last_journal_id_fkey"
            columns: ["last_journal_id"]
            referencedRelation: "t_journals"
            referencedColumns: ["id"]
          },
        ]
      }
      t_role_permissions: {
        Row: {
          can_create: boolean
          can_delete: boolean
          can_read: boolean
          can_update: boolean
          created_at: string
          created_by: string | null
          feature_id: number
          id: number
          role_id: number
          updated_at: string
        }
        Insert: {
          can_create?: boolean
          can_delete?: boolean
          can_read?: boolean
          can_update?: boolean
          created_at?: string
          created_by?: string | null
          feature_id: number
          id?: never
          role_id: number
          updated_at?: string
        }
        Update: {
          can_create?: boolean
          can_delete?: boolean
          can_read?: boolean
          can_update?: boolean
          created_at?: string
          created_by?: string | null
          feature_id?: number
          id?: never
          role_id?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "t_role_permissions_feature_id_fkey"
            columns: ["feature_id"]
            referencedRelation: "m_features"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_role_permissions_role_id_fkey"
            columns: ["role_id"]
            referencedRelation: "m_roles"
            referencedColumns: ["id"]
          },
        ]
      }
      t_user_access_override: {
        Row: {
          can_create: boolean | null
          can_delete: boolean | null
          can_read: boolean | null
          can_update: boolean | null
          created_at: string
          created_by: string | null
          feature_id: number
          id: number
          is_override_active: boolean
          updated_at: string
          user_id: string
        }
        Insert: {
          can_create?: boolean | null
          can_delete?: boolean | null
          can_read?: boolean | null
          can_update?: boolean | null
          created_at?: string
          created_by?: string | null
          feature_id: number
          id?: never
          is_override_active?: boolean
          updated_at?: string
          user_id: string
        }
        Update: {
          can_create?: boolean | null
          can_delete?: boolean | null
          can_read?: boolean | null
          can_update?: boolean | null
          created_at?: string
          created_by?: string | null
          feature_id?: number
          id?: never
          is_override_active?: boolean
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "t_user_access_override_created_by_fkey"
            columns: ["created_by"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_user_access_override_feature_id_fkey"
            columns: ["feature_id"]
            referencedRelation: "m_features"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_user_access_override_user_id_fkey"
            columns: ["user_id"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      t_vat_settlements: {
        Row: {
          created_at: string
          created_by: string | null
          id: number
          input_vat: number
          journal_id: number
          net_vat: number
          output_vat: number
          period_id: number
          status: string
          void_journal_id: number | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          id?: never
          input_vat: number
          journal_id: number
          net_vat: number
          output_vat: number
          period_id: number
          status?: string
          void_journal_id?: number | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          id?: never
          input_vat?: number
          journal_id?: number
          net_vat?: number
          output_vat?: number
          period_id?: number
          status?: string
          void_journal_id?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "t_vat_settlements_created_by_fkey"
            columns: ["created_by"]
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_vat_settlements_journal_id_fkey"
            columns: ["journal_id"]
            referencedRelation: "t_journals"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_vat_settlements_period_id_fkey"
            columns: ["period_id"]
            referencedRelation: "m_periods"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "t_vat_settlements_void_journal_id_fkey"
            columns: ["void_journal_id"]
            referencedRelation: "t_journals"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      account_map: { Args: { p_key: string }; Returns: number }
      account_net: {
        Args: {
          p_account_id: number
          p_exclude_closing?: boolean
          p_from: string
          p_to: string
        }
        Returns: number
      }
      activate_asset: { Args: { p_id: number }; Returns: undefined }
      aging: {
        Args: { p_as_of: string; p_side: string }
        Returns: {
          bucket: string
          currency: string
          days_overdue: number
          doc_id: number
          doc_no: string
          doc_type: string
          due_date: string
          invoice_date: string
          open_amount: number
          open_base: number
          partner: string
          partner_id: number
        }[]
      }
      allocate_payment: {
        Args: { p_amount: number; p_invoice_id: number; p_payment_id: number }
        Returns: undefined
      }
      apply_allocation: { Args: { p_alloc_id: number }; Returns: undefined }
      apply_credit_note: {
        Args: {
          p_amount: number
          p_date?: string
          p_invoice_id: number
          p_note_id: number
        }
        Returns: number
      }
      apply_note_internal: {
        Args: {
          p_amount: number
          p_date: string
          p_invoice_id: number
          p_note_id: number
        }
        Returns: number
      }
      apply_to_invoice: {
        Args: { p_amount: number; p_invoice_id: number }
        Returns: {
          approved_by: string | null
          attachment_path: string | null
          cost_center_id: number | null
          created_at: string
          created_by: string | null
          currency: string
          discount_total: number
          doc_no: string | null
          doc_type: string
          due_date: string | null
          fx_rate: number
          id: number
          invoice_date: string
          journal_id: number | null
          note: string | null
          original_invoice_id: number | null
          paid_amount: number
          partner_id: number
          posted_at: string | null
          posted_by: string | null
          project_id: number | null
          reference: string | null
          reject_reason: string | null
          status: string
          submitted_at: string | null
          subtotal: number
          tax_invoice_date: string | null
          tax_invoice_no: string | null
          tax_total: number
          term_id: number | null
          total: number
          updated_at: string
          void_journal_id: number | null
          void_reason: string | null
          wht_total: number
        }
        SetofOptions: {
          from: "*"
          to: "t_invoices"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      approve_budget: { Args: { p_id: number }; Returns: undefined }
      asset_accumulated: { Args: { p_asset_id: number }; Returns: number }
      asset_dep_amount: {
        Args: {
          a: Database["public"]["Tables"]["t_assets"]["Row"]
          p_accum: number
          p_n: number
        }
        Returns: number
      }
      asset_month_index: {
        Args: {
          a: Database["public"]["Tables"]["t_assets"]["Row"]
          p_date: string
        }
        Returns: number
      }
      asset_register_summary: {
        Args: never
        Returns: {
          accumulated: number
          asset_id: number
          book_value: number
        }[]
      }
      asset_schedule: {
        Args: { p_id: number }
        Returns: {
          accumulated: number
          amount: number
          book_value: number
          month: string
          posted: boolean
        }[]
      }
      auto_match_statement: {
        Args: { p_statement_id: number }
        Returns: number
      }
      balance_sheet: {
        Args: { p_as_of: string }
        Returns: {
          account_id: number
          account_type: string
          balance: number
          code: string
          is_postable: boolean
          name: string
          parent_id: number
          subtype: string
        }[]
      }
      bank_amount: {
        Args: {
          p_currency: string
          p_line: Database["public"]["Tables"]["t_journal_lines"]["Row"]
        }
        Returns: number
      }
      bank_balances: {
        Args: { p_as_of?: string }
        Returns: {
          base: number
          code: string
          currency: string
          fc: number
          id: number
          is_active: boolean
          kind: string
          name: string
        }[]
      }
      base_currency: { Args: never; Returns: string }
      book_statement_line: {
        Args: {
          p_account_id: number
          p_description?: string
          p_line_id: number
        }
        Returns: number
      }
      budget_vs_actual: {
        Args: {
          p_budget_id: number
          p_from_period?: number
          p_to_period?: number
        }
        Returns: {
          account_id: number
          account_type: string
          actual: number
          budget: number
          code: string
          name: string
          used_pct: number
          variance: number
        }[]
      }
      can_edit_budget: { Args: { p_id: number }; Returns: boolean }
      can_edit_cash_txn: { Args: { p_id: number }; Returns: boolean }
      can_edit_claim: { Args: { p_id: number }; Returns: boolean }
      can_edit_invoice: { Args: { p_id: number }; Returns: boolean }
      can_edit_journal: { Args: { p_journal_id: number }; Returns: boolean }
      can_edit_payment: { Args: { p_id: number }; Returns: boolean }
      can_edit_statement: { Args: { p_id: number }; Returns: boolean }
      can_grant: {
        Args: {
          p_create: boolean
          p_delete: boolean
          p_feature_id: number
          p_read: boolean
          p_update: boolean
        }
        Returns: boolean
      }
      can_read_ledger: { Args: never; Returns: boolean }
      can_see_claim: { Args: { p_employee: string }; Returns: boolean }
      cash_flow: {
        Args: { p_from: string; p_to: string }
        Returns: {
          account_id: number
          amount: number
          code: string
          name: string
          section: string
        }[]
      }
      cash_flow_section: { Args: { p_subtype: string }; Returns: string }
      cash_month_end: {
        Args: { p_months?: number; p_to: string }
        Returns: {
          balance: number
          month: string
        }[]
      }
      cash_txn_post: { Args: { p_id: number }; Returns: undefined }
      close_fiscal_year: { Args: { p_year_id: number }; Returns: number }
      close_period: { Args: { p_period_id: number }; Returns: undefined }
      company_today: { Args: never; Returns: string }
      dashboard_summary: {
        Args: { p_from: string; p_to: string }
        Returns: Json
      }
      decide_cash_txn: {
        Args: { p_approve: boolean; p_id: number; p_reason?: string }
        Returns: undefined
      }
      decide_document: {
        Args: {
          p_approve: boolean
          p_id: number
          p_kind: string
          p_reason?: string
        }
        Returns: undefined
      }
      decide_expense_claim: {
        Args: { p_approve: boolean; p_id: number; p_reason?: string }
        Returns: undefined
      }
      decide_invoice: {
        Args: { p_approve: boolean; p_id: number; p_reason?: string }
        Returns: undefined
      }
      decide_journal: {
        Args: { p_approve: boolean; p_id: number; p_reason?: string }
        Returns: undefined
      }
      decide_payment: {
        Args: { p_approve: boolean; p_id: number; p_reason?: string }
        Returns: undefined
      }
      demo_act: { Args: { p_date: string; p_user: string }; Returns: undefined }
      demo_cash: {
        Args: {
          p_approver: string
          p_bank: string
          p_date: string
          p_desc: string
          p_direction: string
          p_lines: Json
          p_maker: string
          p_partner?: string
        }
        Returns: number
      }
      demo_invoice: {
        Args: {
          p_date: string
          p_lines: Json
          p_orig?: number
          p_partner: string
          p_ref?: string
          p_type: string
        }
        Returns: number
      }
      demo_journal: {
        Args: {
          p_approver: string
          p_date: string
          p_kind?: string
          p_lines: Json
          p_maker: string
          p_memo: string
          p_submit?: boolean
        }
        Returns: number
      }
      demo_pay: {
        Args: {
          p_approver: string
          p_bank: string
          p_date: string
          p_direction: string
          p_invoices: number[]
          p_maker: string
          p_partial?: number
          p_wht_code?: string
        }
        Returns: number
      }
      demo_post_invoice: {
        Args: { p_approver: string; p_id: number; p_maker: string }
        Returns: {
          approved_by: string | null
          attachment_path: string | null
          cost_center_id: number | null
          created_at: string
          created_by: string | null
          currency: string
          discount_total: number
          doc_no: string | null
          doc_type: string
          due_date: string | null
          fx_rate: number
          id: number
          invoice_date: string
          journal_id: number | null
          note: string | null
          original_invoice_id: number | null
          paid_amount: number
          partner_id: number
          posted_at: string | null
          posted_by: string | null
          project_id: number | null
          reference: string | null
          reject_reason: string | null
          status: string
          submitted_at: string | null
          subtotal: number
          tax_invoice_date: string | null
          tax_invoice_no: string | null
          tax_total: number
          term_id: number | null
          total: number
          updated_at: string
          void_journal_id: number | null
          void_reason: string | null
          wht_total: number
        }
        SetofOptions: {
          from: "*"
          to: "t_invoices"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      demo_seed_run: { Args: never; Returns: Json }
      demo_user: {
        Args: { p_email: string; p_name: string; p_role: string }
        Returns: string
      }
      dispose_asset: {
        Args: {
          p_bank_id?: number
          p_date: string
          p_id: number
          p_note?: string
          p_proceeds?: number
        }
        Returns: undefined
      }
      doc_control_account: { Args: { p_doc_type: string }; Returns: number }
      doc_feature: { Args: { p_doc_type: string }; Returns: string }
      doc_sign: { Args: { p_doc_type: string }; Returns: number }
      draft_target: {
        Args: { p_id: number; p_table: string }
        Returns: undefined
      }
      ensure_fiscal_year: { Args: { p_year: number }; Returns: number }
      finish_statement: { Args: { p_statement_id: number }; Returns: undefined }
      fx_rate_on: {
        Args: { p_currency: string; p_date: string }
        Returns: number
      }
      general_ledger: {
        Args: {
          p_account_id: number
          p_cost_center_id?: number
          p_from: string
          p_to: string
        }
        Returns: {
          balance: number
          cost_center: string
          credit: number
          currency: string
          debit: number
          doc_no: string
          fc_amount: number
          journal_date: string
          journal_id: number
          kind: string
          line_id: number
          memo: string
          partner: string
          reference: string
          source_id: number
          source_type: string
        }[]
      }
      get_users_with_email: {
        Args: never
        Returns: {
          avatar_url: string
          banned_until: string
          created_at: string
          email: string
          employee_code: string
          full_name: string
          id: string
          is_superadmin: boolean
          role_id: number
          role_name: string
        }[]
      }
      gl_create: {
        Args: {
          p_allow_closed?: boolean
          p_date: string
          p_kind: string
          p_lines: Json
          p_memo: string
          p_reference: string
          p_source_id: number
          p_source_type: string
        }
        Returns: number
      }
      gl_post_journal: {
        Args: { p_allow_closed?: boolean; p_id: number }
        Returns: undefined
      }
      gl_reverse: {
        Args: { p_date: string; p_id: number; p_memo: string }
        Returns: number
      }
      has_any_access: { Args: never; Returns: boolean }
      has_permission: {
        Args: { p_action: string; p_feature_key: string }
        Returns: boolean
      }
      income_statement: {
        Args: {
          p_cost_center_id?: number
          p_from: string
          p_project_id?: number
          p_to: string
        }
        Returns: {
          account_id: number
          account_type: string
          amount: number
          code: string
          is_postable: boolean
          name: string
          parent_id: number
          subtype: string
        }[]
      }
      invoice_post: { Args: { p_id: number }; Returns: undefined }
      invoice_recalc: { Args: { p_id: number }; Returns: undefined }
      is_admin: { Args: never; Returns: boolean }
      is_banned: { Args: never; Returns: boolean }
      is_superadmin: { Args: never; Returns: boolean }
      journal_check: {
        Args: { p_id: number; p_manual: boolean }
        Returns: number
      }
      journal_reconciled: { Args: { p_journal_id: number }; Returns: boolean }
      log_client_error: {
        Args: { p_context?: Json; p_message: string; p_source: string }
        Returns: undefined
      }
      match_statement_line: {
        Args: { p_journal_line_id?: number; p_line_id: number }
        Returns: undefined
      }
      my_rank: { Args: never; Returns: number }
      natural_sign: { Args: { p_type: string }; Returns: number }
      next_doc_no: { Args: { p_date: string; p_kind: string }; Returns: string }
      notify_user: {
        Args: {
          p_body: string
          p_link: string
          p_title: string
          p_user: string
        }
        Returns: undefined
      }
      notify_users: {
        Args: {
          p_action: string
          p_body: string
          p_feature: string
          p_link: string
          p_title: string
        }
        Returns: undefined
      }
      open_fiscal_year: { Args: { p_year: number }; Returns: number }
      outranks: { Args: { p_user_id: string }; Returns: boolean }
      partner_exposure: { Args: { p_partner_id: number }; Returns: number }
      partner_payable_exposure: {
        Args: { p_partner_id: number }
        Returns: number
      }
      partner_statement: {
        Args: {
          p_from: string
          p_partner_id: number
          p_side: string
          p_to: string
        }
        Returns: {
          balance: number
          credit: number
          debit: number
          doc_no: string
          journal_date: string
          kind: string
          memo: string
          reference: string
        }[]
      }
      pay_expense_claim: {
        Args: { p_bank_id: number; p_date?: string; p_id: number }
        Returns: undefined
      }
      payment_check: {
        Args: { p_id: number }
        Returns: {
          allocated_amount: number
          amount: number
          approved_by: string | null
          bank_account_id: number
          created_at: string
          created_by: string | null
          currency: string
          direction: string
          doc_no: string | null
          fx_rate: number
          id: number
          journal_id: number | null
          note: string | null
          partner_id: number
          payment_date: string
          posted_at: string | null
          posted_by: string | null
          reference: string | null
          reject_reason: string | null
          status: string
          submitted_at: string | null
          updated_at: string
          void_journal_id: number | null
          void_reason: string | null
          wht_amount: number
          wht_base: number | null
          wht_slip_no: string | null
          wht_tax_id: number | null
        }
        SetofOptions: {
          from: "*"
          to: "t_payments"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      payment_post: { Args: { p_id: number }; Returns: undefined }
      payment_target_ok: {
        Args: { p_direction: string; p_doc_type: string }
        Returns: boolean
      }
      pending_approvals: {
        Args: never
        Returns: {
          amount: number
          base_amount: number
          currency: string
          doc_no: string
          id: number
          kind: string
          partner: string
          requested_by: string
          requested_by_id: string
          submitted_at: string
          title: string
        }[]
      }
      period_checklist: {
        Args: { p_period_id: number }
        Returns: {
          blocking: boolean
          count: number
          item: string
          link: string
        }[]
      }
      post_transfer: { Args: { p_id: number }; Returns: undefined }
      posting_period: {
        Args: { p_allow_closed?: boolean; p_date: string }
        Returns: number
      }
      public_demo_mode: { Args: never; Returns: boolean }
      reopen_budget: { Args: { p_id: number }; Returns: undefined }
      reopen_fiscal_year: { Args: { p_year_id: number }; Returns: undefined }
      reopen_period: { Args: { p_period_id: number }; Returns: undefined }
      reopen_statement: { Args: { p_statement_id: number }; Returns: undefined }
      report_gate: { Args: { p_feature?: string }; Returns: undefined }
      revalue_fx: { Args: { p_date: string }; Returns: Json }
      reverse_journal: {
        Args: { p_date?: string; p_id: number; p_reason?: string }
        Returns: number
      }
      run_depreciation: { Args: { p_period_id: number }; Returns: Json }
      run_recurring_journals: { Args: { p_as_of?: string }; Returns: number }
      save_cash_txn_draft: {
        Args: { p_header: Json; p_id?: number; p_lines: Json }
        Returns: number
      }
      save_invoice_draft: {
        Args: { p_header: Json; p_id?: number; p_lines: Json }
        Returns: number
      }
      save_journal_draft: {
        Args: { p_header: Json; p_id?: number; p_lines: Json }
        Returns: number
      }
      save_payment_draft: {
        Args: { p_header: Json; p_id?: number; p_lines: Json }
        Returns: number
      }
      save_recurring_journal: {
        Args: { p_header: Json; p_id?: number; p_lines: Json }
        Returns: number
      }
      seed_asset_categories: { Args: never; Returns: undefined }
      seed_default_master: { Args: never; Returns: undefined }
      seed_demo_data: { Args: never; Returns: Json }
      set_tax_invoice_no: {
        Args: { p_date: string; p_id: number; p_no: string }
        Returns: undefined
      }
      settle_fx: {
        Args: {
          p_amount: number
          p_date: string
          p_invoice: Database["public"]["Tables"]["t_invoices"]["Row"]
          p_other_rate: number
          p_source_id: number
          p_source_type: string
        }
        Returns: number
      }
      settle_vat: { Args: { p_period_id: number }; Returns: number }
      statement_book_entries: {
        Args: { p_statement_id: number }
        Returns: {
          amount: number
          doc_no: string
          journal_date: string
          journal_line_id: number
          memo: string
          reference: string
        }[]
      }
      submit_cash_txn: { Args: { p_id: number }; Returns: string }
      submit_expense_claim: { Args: { p_id: number }; Returns: undefined }
      submit_invoice: { Args: { p_id: number }; Returns: string }
      submit_journal: { Args: { p_id: number }; Returns: string }
      submit_payment: { Args: { p_id: number }; Returns: string }
      superadmin_bootstrap: {
        Args: { p_email: string; p_password: string }
        Returns: string
      }
      superadmin_overview: { Args: never; Returns: Json }
      superadmin_reset_data: { Args: never; Returns: undefined }
      trial_balance: {
        Args: {
          p_cost_center_id?: number
          p_exclude_closing?: boolean
          p_from: string
          p_project_id?: number
          p_to: string
        }
        Returns: {
          account_id: number
          account_type: string
          closing: number
          code: string
          credit: number
          debit: number
          is_postable: boolean
          name: string
          opening: number
          parent_id: number
          subtype: string
        }[]
      }
      unapply_credit_note: {
        Args: { p_application_id: number; p_date?: string }
        Returns: undefined
      }
      unapply_from_invoice: {
        Args: { p_amount: number; p_invoice_id: number }
        Returns: undefined
      }
      user_can: {
        Args: { p_action: string; p_feature_key: string; p_user: string }
        Returns: boolean
      }
      vat_report: {
        Args: { p_period_id: number }
        Returns: {
          doc_date: string
          doc_id: number
          doc_kind: string
          doc_no: string
          npwp: string
          partner: string
          side: string
          tax_base: number
          tax_code: string
          tax_invoice_date: string
          tax_invoice_no: string
          vat: number
        }[]
      }
      void_cash_txn: {
        Args: { p_date?: string; p_id: number; p_reason: string }
        Returns: undefined
      }
      void_invoice: {
        Args: { p_date?: string; p_id: number; p_reason: string }
        Returns: undefined
      }
      void_payment: {
        Args: { p_date?: string; p_id: number; p_reason: string }
        Returns: undefined
      }
      void_transfer: {
        Args: { p_date?: string; p_id: number; p_reason: string }
        Returns: undefined
      }
      void_vat_settlement: { Args: { p_id: number }; Returns: undefined }
      wht_report: {
        Args: { p_from: string; p_to: string }
        Returns: {
          doc_date: string
          doc_id: number
          doc_no: string
          gross: number
          npwp: string
          partner: string
          side: string
          slip_no: string
          tax_code: string
          wht: number
          wht_type: string
        }[]
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
