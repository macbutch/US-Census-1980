require 'rubygems'
require 'builder'
require 'active_support/all'
require 'csv'
# require 'faster_csv'

require_relative 'fips_codes'

def getNextField(file, size)
  str = ""
  for i in (1..size)
    c = file.getc
    str += c 
  end
  str
end

def getAbsField(file, start, size) 
  file.seek start
  getNextField(file, size)
end

def getFileId(file)
  getAbsField(file, 0, 5)
end

def decode_summary_level(level)
  {
    "01" => "United States",
    "02" => "Region",
    "03" => "Division",
    "04" => "State",
    "05" => "SCSA",
    "06" => "SCSA/State",
    "07" => "SMSA (Standard Municipal Statistical Area)",
    "08" => "SMSA/State",
    "09" => "Urbanized Area",
    "10" => "Urbanized Area/State",
    "11" => "State/County",
    "12" => "State/County/MCD (CCD)",
    "13" => "State/County/MCD (CCD)/Place",
    "14" => "State/County/MCD (CCD)/Place/Tract (BNA)",
    "15" => "State/County/MCD (CCD)/Place/Tract (BNA)/BG",
    "16" => "State/County/MCD (CCD)/Place/Tract (BNA)/ED",
    "17" => "State/SMSA/County",
    "18" => "State/SMSA/County/MCD (CCD)",
    "19" => "State/SMSA/County/MCD (CCD)/Place",
    "20" => "State/SMSA/County/MCD (CCD)/Place/Tract (BNA)",
    "20" => "State/SMSA/County/MCD (CCD)/Place/Tract (BNA)/Block",
    "21" => "State/SMSA/County/MCD (CCD)/Place/Tract (BNA)/ED"
  }[level]
end

class CensusLogicalSegment

  attr_accessor :raw

  def initialize(raw)
    @raw = raw
  end

end


class CensusLogicalRecord
  attr_accessor :raw, :segments

  OFF = {
    :families_start => 378,
    :area_name_start => 144,
    :area_name_length => 60,
    :county_code_start => 39,
    :tract_start => 49,
    :persons_start => 252,
    :enrolment_start => 4134,
    :median_household_income_start => 5949,
    :median_family_income_start => 6408,
    :poverty_status_start => 7191,
    :median_gross_rent_start => 10056,
    :sex_by_age_start => 675
  }

  def initialize(raw)
    @raw = raw

    # processing segments
    @segments = []
    for i in (0..10)
      segment = CensusLogicalSegment.new(@raw[i * 20160,2016])
      @segments << segment
    end
  end

  def file_id
    @raw[0, 5]
  end

  def record_type
    @raw[5, 4]
  end

  def summary_level
    code = @raw[9, 2]
    { :code => code, :text => decode_summary_level(code) }
  end

  def state
    code = @raw[33, 2]
    { 
      :fips_code => code, 
      :name => get_state_name(code) 
    }
  end

  def zip
    @raw[82, 5]
  end

  def area
    @raw[OFF[:area_name_start], OFF[:area_name_length]].strip
  end

  def county
    code = (state[:fips_code] + @raw[OFF[:county_code_start], 3]).to_i
    { :fips_code => code, :text => get_county_name(code) }
  end

  def is_tract
    summary_level[:code] == "20" || summary_level[:code] == "14"
  end

  def field(start, field = 0, size = 9) 
    @raw[OFF[start] + (size * field), size]
  end

  def field_i(start, field = 0, size = 9) 
    @raw[OFF[start] + (size * field), size].to_i
  end

  def one_big_hash
    {
      :area    => area,
      :tract   => tract,
      :county  => county,
      :persons => persons,
      :income  => income,
      :poverty => poverty_status,
      :median_gross_rent =>
                  median_gross_rent,
      :enrollment =>
                  enrolment,
      :families =>
                  families,
      :sex_by_age =>
                  sex_by_age
    }
  end

  def tract
    code = field(:tract_start, 0, 6) #@raw[OFF[:tract_start], 6]
    if code[4,2].strip.length > 0
      text = "#{code[0,4]}.#{code[4,2]}"
    else
      text = code
    end
    { :raw => code.strip, :text => text.strip }
  end

  def persons
    # total =  @segments[0].raw[OFF[:persons_start], 9].to_i
    # inside = @segments[0].raw[OFF[:persons_start] + 9, 9].to_i
    # rural =  @segments[0].raw[OFF[:persons_start] + 18, 9].to_i
    # unweighted = @segments[0].raw[OFF[:persons_start] + 27, 9].to_i
    # hundred_percent = @segments[0].raw[OFF[:persons_start] + 36, 9].to_i
    { 
      :total  => field_i(:persons_start), 
      :inside => field_i(:persons_start, 1), 
      :rural  => field_i(:persons_start, 2), 
      :urban  => field_i(:persons_start) - field_i(:persons_start, 2), 
      :unweight_sample_count => field_i(:persons_start, 3), 
      :hundred_percent_count => field_i(:persons_start, 4)
    }
  end

  def enrolment
    # elementary = @raw[OFF[:enrolment_start], 9].to_i
    # high_school_1_to_3 = @raw[OFF[:enrolment_start] + 9, 9].to_i
    # high_school_4 = @raw[OFF[:enrolment_start] + 18, 9].to_i
    # college_1_to_3  = @raw[OFF[:enrolment_start] + 27, 9].to_i
    # college_4 = @raw[OFF[:enrolment_start] + 36, 9].to_i
    {
      :elementary         => field_i(:enrolment_start),
      :high_school_1_to_3 => field_i(:enrolment_start, 1),
      :high_school_4      => field_i(:enrolment_start, 2),
      :college_1_to_3     => field_i(:enrolment_start, 3),
      :college_4          => field_i(:enrolment_start, 4)
    }
  end

  
  def income
    { 
      # :median_household_1979 => @raw[OFF[:median_household_income_start], 9].to_i,
      # :median_family_1979 => @raw[OFF[:median_family_income_start], 9].to_i
      :median_household_1979 => field_i(:median_household_income_start),
      :median_family_1979    => field_i(:median_family_income_start)
    }
  end

  def median_gross_rent
    field_i(:median_gross_rent_start)
  end

  def families
    field_i(:families_start)
  end

  FEMALE_OFFSET = 26
  def extract_sex(group = 0)
    {
        :male   => field_i(:sex_by_age_start, group),
        :female => field_i(:sex_by_age_start, group + FEMALE_OFFSET)
    }
  end

  def sex_by_age
    {
      'below_1'      => extract_sex,
      'age_1_and_2'  => extract_sex(1),
      'age_3_and_4'  => extract_sex(2),
      'age_5'        => extract_sex(3),
      'age_6'        => extract_sex(4),
      'age_7_to_9'   => extract_sex(5),
      'age_10_to_13' => extract_sex(6),
      'age_14'       => extract_sex(7)
    }
  end

  def poverty_status
    {
      :above_poverty => {
        :name => 'above_poverty_lvl',
        :display_name => 'Above Poverty Level',
        :children_under_6_and_6_to_17 => field_i(:poverty_status_start, 0),
        :children_under_6 => field_i(:poverty_status_start, 1),
        :children_6_to_17 => field_i(:poverty_status_start, 2),
        :no_children => field_i(:poverty_status_start, 3)
      },
      :below_poverty => {
        :name => 'below_poverty_lvl',
        :display_name => 'Below Poverty Level',
        :children_under_6_and_6_to_17 => field_i(:poverty_status_start, 4),
        :children_under_6 => field_i(:poverty_status_start, 5),
        :children_6_to_17 => field_i(:poverty_status_start, 6),
        :no_children => field_i(:poverty_status_start, 7)
      },
      :female_householder => {
        :name => 'female_householder',
        :display_name => 'Female Householder',
        :children_under_6_and_6_to_17 => field_i(:poverty_status_start, 8),
        :children_under_6 => field_i(:poverty_status_start, 9),
        :children_6_to_17 => field_i(:poverty_status_start, 10),
        :no_children => field_i(:poverty_status_start, 11)
      },
      :no_husband_present => {
        :name => 'female_householder_no_husband',
        :display_name => 'Female Householder (No Husband Present)',
        :children_under_6_and_6_to_17 => field_i(:poverty_status_start, 12),
        :children_under_6 => field_i(:poverty_status_start, 13),
        :children_6_to_17 => field_i(:poverty_status_start, 14),
        :no_children => field_i(:poverty_status_start, 15)
      }
    }
  end

end

def write_poverty_level xml, hash
  xml << hash.to_xml(options = {
    :skip_instruct => true,
    :root => hash[:name]
  })
end

def poverty_level_array hash
  [
    hash[:children_under_6_and_6_to_17],
    hash[:children_under_6],
    hash[:children_6_to_17],
    hash[:no_children]
  ]
end

f = File.open(ARGV[0], "r") 

# x = Builder::XmlMarkup.new(:target => $stdout, :indent => 2)
# x.records do | xml_records |

csv_string = CSV.generate do |csv|
  csv << [
    "Area", 
    "Tract", 
    "County", 
    "Persons", 
    "Median Household Income 1979",
    "Median Family Income 1979",
    "Median Gross Rent",
    "High School Graduates",
    "Families",
    "Above Poverty Level - Children Under 6 and 6 to 17",
    "Above Poverty Level - Children Under 6",
    "Above Poverty Level - Children Under 6 to 17",
    "Above Poverty Level - No Children",
    "Below Poverty Level - Children Under 6 and 6 to 17",
    "Below Poverty Level - Children Under 6",
    "Below Poverty Level - Children Under 6 to 17",
    "Below Poverty Level - No Children",
    "Female Householder - Children Under 6 and 6 to 17",
    "Female Householder - Children Under 6",
    "Female Householder - Children Under 6 to 17",
    "Female Householder - No Children",
    "Female Householder (No Husband Present) - Children Under 6 and 6 to 17",
    "Female Householder (No Husband Present) - Children Under 6",
    "Female Householder (No Husband Present) - Children Under 6 to 17",
    "Female Householder (No Husband Present) - No Children"
  ]
  begin
    record = CensusLogicalRecord.new(f.gets)
    # if record.is_tract
      csv_record = [
        record.area,
        record.tract[:text],
        record.county[:text],
        record.persons[:total],
        record.income[:median_household_1979],
        record.income[:median_family_1979],
        record.median_gross_rent,
        record.enrolment[:high_school_4],
        record.families
      ]
      csv_record << poverty_level_array(record.poverty_status[:above_poverty])
      csv_record << poverty_level_array(record.poverty_status[:below_poverty])
      csv_record << poverty_level_array(record.poverty_status[:female_householder])
      csv_record << poverty_level_array(record.poverty_status[:no_husband_present])
      csv << csv_record.flatten

      #   x << record.sex_by_age.to_xml(options = {
      #     :skip_instruct => true, 
      #     :root => :sex
      #   })
      # end
    # end
  end while !f.eof
end
f.close
puts csv_string
