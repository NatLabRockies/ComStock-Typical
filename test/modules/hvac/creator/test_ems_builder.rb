require_relative '../../../helpers/minitest_helper'

class TestHVACCreatorEmsBuilder < Minitest::Test
  def setup
    @model = OpenStudio::Model::Model.new
    @ctx = OpenstudioStandards::HVAC::BuildContext.new(@model)
    @ems = OpenstudioStandards::HVAC::EmsBuilder
  end

  def full_spec
    {
      sensors: [{ name: 'OAT', keyname: 'Environment', variable: 'Site Outdoor Air Drybulb Temperature' }],
      internal_vars: [{ name: 'ZnVol', data_type: 'Zone Air Volume', key_name: 'Some Zone' }],
      global_vars: ['MyResult'],
      actuators: [{ name: 'SetptAct', component_name: 'EMS Target Sch', component_type: 'Schedule:Constant',
                    control_type: 'Schedule Value', create_schedule_constant: 20.0, schedule_type_limit: 'Temperature' }],
      programs: [{ name: 'ResetProg', body: "SET MyResult = OAT * 0.5 + 10,\nSET SetptAct = MyResult" }],
      calling_managers: [{ name: 'ResetCM', calling_point: 'BeginTimestepBeforePredictor', program_names: ['ResetProg'] }],
      output_variables: [{ name: 'MyResult Output', ems_var_name: 'MyResult', data_type: 'Averaged',
                           update_freq: 'SystemTimestep', units: 'C' }]
    }
  end

  def test_builds_all_object_kinds
    @ems.build(full_spec, @ctx)
    assert_equal(1, @model.getEnergyManagementSystemSensors.size)
    assert_equal(1, @model.getEnergyManagementSystemInternalVariables.size)
    assert_equal(1, @model.getEnergyManagementSystemGlobalVariables.size)
    assert_equal(1, @model.getEnergyManagementSystemActuators.size)
    assert_equal(1, @model.getEnergyManagementSystemPrograms.size)
    assert_equal(1, @model.getEnergyManagementSystemProgramCallingManagers.size)
    assert_equal(1, @model.getEnergyManagementSystemOutputVariables.size)
  end

  def test_sensor_fields
    @ems.build({ sensors: [{ name: 'OAT', keyname: 'Environment', variable: 'Site Outdoor Air Drybulb Temperature' }] }, @ctx)
    sensor = @model.getEnergyManagementSystemSensors.first
    assert_equal('OAT', sensor.name.get)
    assert_equal('Environment', sensor.keyName)
    assert_equal('Site Outdoor Air Drybulb Temperature', sensor.outputVariableOrMeterName)
  end

  def test_actuator_creates_constant_schedule
    @ems.build({ actuators: [{ name: 'A', component_name: 'New Sch', component_type: 'Schedule:Constant',
                               control_type: 'Schedule Value', create_schedule_constant: 3.0 }] }, @ctx)
    schedule = @model.getScheduleConstantByName('New Sch')
    assert(schedule.is_initialized, 'a constant schedule is created for the actuator')
    assert_in_delta(3.0, schedule.get.value, 0.001)
    assert_equal('New Sch', @model.getEnergyManagementSystemActuators.first.actuatedComponent.get.name.get)
  end

  # The actuator's schedule type limit reaches the created schedule, and the limits object is made
  # if the model does not already carry it.
  def test_actuator_constant_schedule_applies_type_limit
    @ems.build({ actuators: [{ name: 'A', component_name: 'Typed Sch', component_type: 'Schedule:Constant',
                               control_type: 'Schedule Value', create_schedule_constant: 3.0,
                               schedule_type_limit: 'Temperature' }] }, @ctx)
    schedule = @model.getScheduleConstantByName('Typed Sch').get
    assert(schedule.scheduleTypeLimits.is_initialized)
    assert_equal('Temperature', schedule.scheduleTypeLimits.get.name.get)
  end

  def test_actuator_targets_named_component
    existing = OpenStudio::Model::ScheduleConstant.new(@model)
    existing.setName('Existing Sch')
    @ems.build({ actuators: [{ name: 'A', component_name: 'Existing Sch', component_type: 'Schedule:Constant',
                              control_type: 'Schedule Value' }] }, @ctx)
    assert_equal('Existing Sch', @model.getEnergyManagementSystemActuators.first.actuatedComponent.get.name.get)
    assert_equal(1, @model.getScheduleConstants.size, 'existing schedule is reused, not duplicated')
  end

  def test_actuator_unknown_component_raises
    spec = { actuators: [{ name: 'A', component_name: 'Nope', component_type: 'Schedule:Constant', control_type: 'Schedule Value' }] }
    assert_raises(ArgumentError) { @ems.build(spec, @ctx) }
  end

  def test_sensor_dedup
    sensor_spec = { sensors: [{ name: 'OAT', keyname: 'Environment', variable: 'Site Outdoor Air Drybulb Temperature' }] }
    @ems.build(sensor_spec, @ctx)
    @ems.build(sensor_spec, @ctx)
    assert_equal(1, @model.getEnergyManagementSystemSensors.size, 'sensors deduplicate by name')
  end

  def test_calling_manager_unknown_program_raises
    spec = { calling_managers: [{ name: 'CM', calling_point: 'BeginTimestepBeforePredictor', program_names: ['MissingProg'] }] }
    assert_raises(ArgumentError) { @ems.build(spec, @ctx) }
  end

  def test_calling_manager_attaches_programs
    @ems.build(full_spec, @ctx)
    manager = @model.getEnergyManagementSystemProgramCallingManagers.first
    assert_equal('BeginTimestepBeforePredictor', manager.callingPoint)
    assert_equal(1, manager.programs.size)
    assert_equal('ResetProg', manager.programs.first.name.get)
  end

  def test_output_variable_binds_to_program
    @ems.build(full_spec, @ctx)
    output_variable = @model.getEnergyManagementSystemOutputVariables.first
    assert_equal('MyResult', output_variable.emsVariableName)
    assert_equal('Averaged', output_variable.typeOfDataInVariable)
  end

  def test_forward_translates_cleanly
    @ems.build(full_spec, @ctx)
    ft = OpenStudio::EnergyPlus::ForwardTranslator.new
    ft.translateModel(@model)
    assert_equal(0, ft.errors.size, ft.errors.map(&:logMessage).join("\n"))
  end
end
