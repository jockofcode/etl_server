# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Seed admin user
user = User.find_or_initialize_by(email: "admin@example.com")
if user.new_record?
  user.assign_attributes(
    password:              "password123",
    password_confirmation: "password123",
    is_admin:              true
  )
  user.save!
  puts "Created seed user: admin@example.com / password123 (admin)"
elsif !user.is_admin?
  user.update!(is_admin: true)
  puts "Granted admin to existing seed user: admin@example.com"
end
