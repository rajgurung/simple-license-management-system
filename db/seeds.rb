require 'faker'

puts "Seeding database..."

# Create admin user WITHOUT account (admins are not tied to accounts)
admin_user = User.find_or_create_by!(email: ENV.fetch('ADMIN_EMAIL', 'admin@example.com')) do |user|
  user.name = "Admin User"
  user.admin = true
  user.username = ENV.fetch('ADMIN_USERNAME', 'admin')
  user.password = ENV.fetch('ADMIN_PASSWORD', 'AdminPassw0rd!')
end
puts "✓ Admin user created: #{admin_user.username}"

# Create products (global catalog)
products = [
  { name: "vLex Colombia", description: "Legal research database for Colombia" },
  { name: "vLex Costa Rica", description: "Legal research database for Costa Rica" },
  { name: "vLex España", description: "Legal research database for Spain" }
]

products.each do |product_data|
  Product.find_or_create_by!(name: product_data[:name]) do |product|
    product.description = product_data[:description]
  end
end
puts "✓ Created #{Product.count} products"

# Create main demo account: Best Law Firm
best_law_firm = Account.find_or_create_by!(name: "Best Law Firm")

# Create 12 specific users from PDF spec
user_names = [
  "Dean Pendley",
  "Robin Chesterman",
  "Angel Faus",
  "Stu Duff",
  "Kalam Lais",
  "Rose Higgins",
  "Nacho Tinoco",
  "Álvaro Pérez Mompeán",
  "Eserophe Ovie-Okoro",
  "Guillermo Espíndola",
  "Rory Campbell",
  "Davide Bonavita"
]

users = user_names.map do |name|
  email = name.downcase.gsub(' ', '.').gsub('á', 'a').gsub('é', 'e') + "@bestlaw.com"
  User.find_or_create_by!(email: email) do |user|
    user.account = best_law_firm
    user.name = name
    user.admin = false
  end
end
puts "✓ Created #{users.size} users for Best Law Firm"

# Create subscriptions for Best Law Firm
# - vLex Colombia: EXPIRED (2 days ago)
# - vLex España: EXPIRING SOON (7 days from now)
# - vLex Costa Rica: ACTIVE (1 year from now)
colombia = Product.find_by!(name: "vLex Colombia")
costa_rica = Product.find_by!(name: "vLex Costa Rica")
espana = Product.find_by!(name: "vLex España")

# Colombia - Expired
Subscription.find_or_create_by!(
  account: best_law_firm,
  product: colombia
) do |subscription|
  subscription.number_of_licenses = 10
  subscription.issued_at = 3.months.ago
  subscription.expires_at = 2.days.ago
end

# España - Expiring soon (7 days)
Subscription.find_or_create_by!(
  account: best_law_firm,
  product: espana
) do |subscription|
  subscription.number_of_licenses = 10
  subscription.issued_at = 1.month.ago
  subscription.expires_at = 7.days.from_now
end

# Costa Rica - Active
Subscription.find_or_create_by!(
  account: best_law_firm,
  product: costa_rica
) do |subscription|
  subscription.number_of_licenses = 10
  subscription.issued_at = Time.current
  subscription.expires_at = 1.year.from_now
end

puts "✓ Created subscriptions for Best Law Firm (1 expired, 1 expiring soon, 1 active)"

# Assign 5 licenses each to vLex Colombia and vLex Costa Rica
users.first(5).each do |user|
  # Assign to Colombia
  LicenseAssignment.find_or_create_by!(
    account: best_law_firm,
    product: colombia,
    user: user
  )

  # Assign to Costa Rica
  LicenseAssignment.find_or_create_by!(
    account: best_law_firm,
    product: costa_rica,
    user: user
  )
end
puts "✓ Assigned 5 licenses each to Colombia and Costa Rica"

# Create second demo account: Towne-Donnelly
towne_donnelly = Account.find_or_create_by!(name: "Towne-Donnelly")

# Create 5 users for Towne-Donnelly
5.times do
  User.find_or_create_by!(email: Faker::Internet.unique.email) do |user|
    user.account = towne_donnelly
    user.name = Faker::Name.name
    user.admin = false
  end
end
puts "✓ Created 5 users for Towne-Donnelly"

# Create one active subscription for Towne-Donnelly
Subscription.find_or_create_by!(
  account: towne_donnelly,
  product: espana
) do |subscription|
  subscription.number_of_licenses = 5
  subscription.issued_at = Time.current
  subscription.expires_at = 6.months.from_now
end
puts "✓ Created active subscription for Towne-Donnelly"

puts "\n" + "="*50
puts "Seed data created successfully!"
puts "="*50
puts "\nAccounts created:"
puts "  1. Best Law Firm (12 users, 3 subscriptions: 1 expired, 1 expiring soon, 1 active)"
puts "  2. Towne-Donnelly (5 users, 1 active subscription)"
puts "\nLogin credentials:"
puts "  Username: #{ENV.fetch('ADMIN_USERNAME', 'admin')}"
puts "  Password: #{ENV.fetch('ADMIN_PASSWORD', 'AdminPassw0rd!')}"
puts "\nAccess the app at: http://localhost:3000"
puts "="*50
