require 'serverspec'

# Required by serverspec
set :backend, :exec

describe "Basic host configuration" do

  it "should have the correct domain" do
    expect(host_inventory['domain']).to eq('foo.com')
  end

end