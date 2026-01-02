-- 1. Profiles table (Auth.users Extension)
CREATE TABLE profiles (
  id uuid REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
  name TEXT,
  phone TEXT,
  address TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Categories table (inventory)
CREATE TABLE categories (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid REFERENCES auth.users ON DELETE CASCADE NOT NULL,
  name TEXT NOT NULL,
  color TEXT DEFAULT '#3b82f6', 
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. Products table 
CREATE TABLE products (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid REFERENCES auth.users ON DELETE CASCADE NOT NULL,
  category_id uuid REFERENCES categories(id) ON DELETE SET NULL, 
  name TEXT NOT NULL,
  bar_code TEXT,
  usd_price DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  stock INTEGER DEFAULT 0,
  min_stock INTEGER DEFAULT 5,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id, bar_code)
);

-- 4. Suscriptions table
CREATE TABLE suscriptions (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid REFERENCES auth.users ON DELETE CASCADE UNIQUE NOT NULL,
  status TEXT CHECK (status IN ('active', 'expired', 'test')) DEFAULT 'test',
  expiration_date TIMESTAMP WITH TIME ZONE NOT NULL,
  plan TEXT DEFAULT 'basic',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 5. Sales table
CREATE TABLE sales (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid REFERENCES auth.users ON DELETE CASCADE NOT NULL,
  total_usd DECIMAL(10, 2) NOT NULL,
  rate_bcv DECIMAL(10, 2) NOT NULL,
  payment_method TEXT NOT NULL CHECK (payment_method IN ('efectivo', 'pago_movil', 'zelle', 'credito', 'punto_de_venta')),
  on_credit BOOLEAN DEFAULT FALSE,
  client_name TEXT, 
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 6. Sales details table
CREATE TABLE sales_details (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  sale_id uuid REFERENCES sales(id) ON DELETE CASCADE NOT NULL,
  product_id uuid REFERENCES products(id) ON DELETE SET NULL,
  quantity INTEGER NOT NULL,
  unit_price_usd DECIMAL(10, 2) NOT NULL
);

-- Enable Row Level Security (RLS)
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE suscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales_details ENABLE ROW LEVEL SECURITY;

-- Function that runs when a new user registers
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  -- 1. Create the profile automatically
  INSERT INTO public.profiles (id, name)
  VALUES (new.id, 'Mi Kiosco Nuevo');

  -- 2. Create the trial subscription (45 days from today)
  INSERT INTO public.suscriptions (user_id, status, expiration_date)
  VALUES (new.id, 'test', now() + interval '45 days');

  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- The trigger that activates the function above
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- ==========================================
-- SECURITY POLICIES (RLS)
-- ==========================================

-- 1. Policy for PROFILES
-- Users can view and edit only their own profile
CREATE POLICY "Users can view own profile" ON profiles 
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON profiles 
  FOR UPDATE USING (auth.uid() = id);


-- 2. Policy for CATEGORIES, PRODUCTS y SALES
-- General rule: You can only view/edit what belongs to you
CREATE POLICY "Users can manage own categories" ON categories 
  FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can manage own products" ON products 
  FOR ALL USING (auth.uid() = user_id);

-- For sales, we allow viewing them as long as they belong to the user.
CREATE POLICY "Users can view own sales" ON sales 
  FOR SELECT USING (auth.uid() = user_id);


-- 3. SAAS LOCK: Sales Insertion Restriction
-- allows inserting sales ONLY if the subscription is active or in trial
CREATE POLICY "Users can create sales only if subscribed" ON sales
  FOR INSERT 
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM suscriptions
      WHERE user_id = auth.uid() 
      AND (status = 'active' OR status = 'test')
      AND expiration_date > now()
    )
  );

-- 4. Policy for SALES_DETAILS
-- Since sales_details does not have a user_id, we link it through the sales table
CREATE POLICY "Users can manage own sales details" ON sales_details
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM sales
      WHERE sales.id = sales_details.sale_id
      AND sales.user_id = auth.uid()
    )
  );

-- 5. Policy for SUSCRIPTIONS
-- The user can only view their subscription status (but cannot manually change it)
CREATE POLICY "Users can view own subscription status" ON suscriptions
  FOR SELECT USING (auth.uid() = user_id);