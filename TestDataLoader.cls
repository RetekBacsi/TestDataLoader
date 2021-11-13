/*
MIT License

Copyright (c) 2021 Gabor Nemeth (RetekBacsi) - gnemeth@me.com
  - additional contribution: Andras Torok, Laszlo Kapczy

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

repository: https://github.com/RetekBacsi/TestDataLoader
*/
@IsTest
public with sharing class TestDataLoader {
  private static final Pattern expressionPattern = Pattern.compile('today\\ *([+-])\\ *(\\d*)\\ *(\\w*)');
  public class TestDataLoaderException extends Exception {} 
  public boolean log = true;
  private XmlStreamReader reader;
  private Map<String,MockObject> pkMap;
  private Map<String,List<ReferenceWrapper>> pkReferenceMap;
  private Map<String,List<MockObject>> typeMap;
  private Map<String,List<MockObject>> globalTypeMap;
  private Set<String> hierarchicalTypeList;
  private Map<String,Set<String>> typeDependency;
  private integer oldTypeMapSize;
  private Map<String,Schema.DescribeSobjectResult> typeCache;
  private Map<String,Id> profileMap;
  private Map<String,List<MockObject>> deferreds;
  private Map<String,List<MockObject>> afterInserts;
  boolean needProfiles = false;
  boolean needPermissionSets = false;
  boolean needPermissionSetLicenses = false;
  boolean needUsers = false;
  private Map<String,Id> requestedUsers;
  private Map<String,Id> userRoleMap;
  private Map<String,Id> permissionsetMap;
  private Map<String,Id> permissionsetLicenseMap;
  private Map<String,MockObject> templateMap;
  boolean needUserRoles = false;
  private Map<String,Map<String,Id>> recordTypeMap;
  private User me;
  public Map<String, List<SObject>> recordMap;
  private boolean initDone = false;

  public Id getIdForPk(String pk){
    if (!pkMap.containsKey(pk)) return null;
    return pkMap.get(pk).getField('Id');
  }

  public void load(String name){
    init();
    parse(name);
    finish();
  }

  public void append(String name){
    if (!initDone) throw new TestDataLoaderException('Invalid Call! Append may be called ONLY after load!');
    afterInserts = new Map<string,List<MockObject>>(); //Need to run only once for each "load"
    typeMap = new Map<String,List<MockObject>>(globalTypeMap);
    parse(name);
    finish();
  }

  public void init(){
    pkMap = new Map<String,MockObject>();
    pkReferenceMap = new Map<String,List<ReferenceWrapper>>();
    typeMap = new  Map<String,List<MockObject>>();
    globalTypeMap = new  Map<String,List<MockObject>>();
    typeDependency = new Map<String,Set<String>>();
    needProfiles = false;
    profileMap = new Map<String,Id>();
    needUserRoles = false;
    userRoleMap = new Map<String,Id>();
    needPermissionSets = false;
    permissionsetMap = new Map<String, Id>();
    needPermissionSetLicenses = false;
    permissionsetLicenseMap = new Map<String, Id>();
    deferreds = new Map<string,List<MockObject>>();
    afterInserts = new Map<string,List<MockObject>>();
    templateMap = new Map<String,MockObject>();
    hierarchicalTypeList = new Set<String>();
    me = new User(Id=UserInfo.getUserId());
    recordMap = new Map<String, List<SObject>>();
    needUsers = false;
    requestedUsers = new Map<String, String>();
    initDone = true;
  }

  public void finish(){
    mapDependencies();
    persist();
  }

  private void initRecordTypeMap(){
    recordTypeMap = new Map<String,Map<String,Id>>();
    for (List<RecordType> rtl : [SELECT Id, SobjectType, DeveloperName, Name FROM RecordType ORDER BY SobjectType, DeveloperName]){
      for (RecordType rt : rtl){
        if (!recordTypeMap.containsKey(rt.SobjectType)) recordTypeMap.put(rt.SobjectType,new Map<String,Id>());
        recordTypeMap.get(rt.SobjectType).put(rt.DeveloperName, rt.Id);
        recordTypeMap.get(rt.SobjectType).put(rt.Name, rt.Id);
      }
    }
  }

  public void parse(String name){
    StaticResource sr = [SELECT Id, Body FROM StaticResource WHERE Name = :name LIMIT 1];
    if (sr == null) throw new TestDataLoaderException('Static resource not found for the name ' + name);
    XmlStreamReader xsr = new XmlStreamReader(sr.Body.toString());
    parse(xsr);
  }

  private void parse(XmlStreamReader reader){
    this.reader = reader;
    assertTag('dataset');
    reader.nextTag();
    while (reader.getLocalName() != 'dataset' || reader.getEventType() != XmlTag.END_ELEMENT){
      parseElement();
      reader.nextTag();
    }
  }

  private void assertTag(String tagName){
    reader.nextTag();
    String nextTag = reader.getLocalName();
    if (nextTag != tagName) throw new TestDataLoaderException('Expected tag ' + tagName + ', got ' + nextTag);
    if (reader.getEventType() != XmlTag.START_ELEMENT) throw new TestDataLoaderException('Expected start element, got ' + reader.getEventType());
  }

  private void parseElement(){
    if (reader.getEventType() != XmlTag.START_ELEMENT) throw new TestDataLoaderException('Expected start element, got ' + reader.getEventType());
    String elementName = reader.getLocalName();
    MockObject mock = new MockObject();
    mock.type = elementName;
    mock.isFinalized = false;
    boolean isTemplate = false;
    boolean isAbstract = false;

    if (log) System.debug('Parsing a ' + elementName);
    for (integer ax = 0; ax < reader.getAttributeCount();ax++){
      String attributeName = reader.getAttributeLocalName(ax);
      String attributeValue = reader.getAttributeValueAt(ax);
      if (attributeName == 'pk') {
        initPKTemplate(mock,attributeValue);
      }else if (attributeName== 'recordType'){
        mock.recordType = attributeValue;
      }else if (attributeName== 'profile'){
        mock.profile = attributeValue;
        needProfiles = true;
      }else if (attributeName == 'userRole'){
        mock.userRole = attributeValue;
        needUserRoles = true;
      } else if (attributeName == 'abstract' && attributeValue.equalsIgnoreCase('true')) {
        isAbstract = true;
      } else if (attributeName == 'template' && attributeValue.equalsIgnoreCase('true')) {
        isTemplate = true;
      } else if (attributeName == 'hierarchy'){
        mock.hierarchy = attributeValue;
        needProfiles = true;
        hierarchicalTypeList.add(elementName);
      } else if (attributeName == 'permissionset'){
        needPermissionSets = true;
        mock.permissionset = attributeValue;
      } else if (attributeName == 'permissionsetLicense'){
        needPermissionSetLicenses = true;
        mock.permissionsetLicense = attributeValue;
      }    
    }

    reader.nextTag();
    while (reader.getEventType() != XmlTag.END_ELEMENT){
      parseField(mock);
      reader.nextTag();
    }
    if (reader.getLocalName() != elementName ) throw new TestDataLoaderException('Mismatched end tag. Expected ' + elementName + ' got ' + reader.getLocalName());
    if (!typeMap.containsKey(elementName)) typeMap.put(elementName,new List<MockObject>());
    if (!isAbstract) typeMap.get(elementName).add(mock);
    if (isTemplate) templateMap.put(elementName, mock);
  }

  // returns the PK definition
  private void parseField(MockObject mock){
    String fieldName = reader.getLocalName();
    String referenceValue;
    boolean isDeferred = false;
    boolean isNull = true;
    for (integer ax = 0; ax < reader.getAttributeCount();ax++){
      String attributeName = reader.getAttributeLocalName(ax);
      String attributeValue = reader.getAttributeValueAt(ax);
      if (attributeName == 'ref') {
        referenceValue = attributeValue;
      }
      if (attributeName == 'deferred' && attributeValue.equalsIgnoreCase('true')){
        isDeferred = true;
      }
      if (attributeName == 'afterInsertValue'){
        addAfterInsertValue(mock, fieldName, attributeValue);
      }
      if (attributeName == 'rtRef') {
        String[] rtRef = attributeValue.split('\\.');
        mock.setField(fieldName, resolveRecordType(rtRef[0], rtRef[1]));
        isNull = false;
      } else if (attributeName == 'userRef'){
        needUsers = true;
        requestedUsers.put(attributeValue, null);
        mock.addUserRef(fieldName, attributeValue);
        isNull = false;
      } else if (attributeName == 'standardPricebook' && attributeValue == 'true'){
        mock.setField(fieldName, Test.getStandardPricebookId());
        isNull = false;
      }
    }
    if (referenceValue != null){
      addPKReference(mock,referenceValue,fieldName,isDeferred);
    }
    reader.next();
    String fullValue = null;
    while (reader.getEventType() == XmlTag.CHARACTERS || reader.getEventType() == XmlTag.CDATA){
      if (reader.hasText()){
        String value = reader.getText();
        if (fullValue == null) fullValue = value;
        else fullValue += value;
        reader.next();
        isNull = false;
      } else {
        break;
      }
    }
    if (fullValue != null) mock.setField(fieldName,fullValue);
    if (reader.getEventType() != XmlTag.END_ELEMENT) throw new TestDataLoaderException('Unsupported content. Expected END_ELEMENT, got ' + reader.getEventType());
    if (isNull) mock.setField(fieldName,null);
    if (reader.getLocalName() != fieldName) throw new TestDataLoaderException('Mismatched end tag. Expected ' + fieldName +  ', got ' + reader.getLocalName());
  }

  private void initPKTemplate(MockObject mock,String name){
    if (this.pkMap.containsKey(name)) throw new TestDataLoaderException('Duplicate foreign key value ' + name);
    this.pkMap.put(name,mock);
    mock.pk = name;
    if (log) System.debug('initialized PK template for ' + name);
  }

  private void addPKReference(MockObject mock, String pk, String field, boolean deferred){
    if (!pkReferenceMap.containsKey(pk)) pkReferenceMap.put(pk,new List<ReferenceWrapper>());
    pkReferenceMap.get(pk).add(new ReferenceWrapper(mock,field,deferred));
    if (deferred){
      if (!mock.hasDeferred) {
        if (!deferreds.containsKey(mock.type)) deferreds.put(mock.type, new List<MockObject>());
        deferreds.get(mock.type).add(mock);
      }
      mock.addDeferredReference(field);
    }
    if (log) System.debug('addPKReference | Added reference for ' + field + ' to ' + pk + ' in object ' + mock);
  }

  private void addAfterInsertValue(MockObject mock, String field, String value){
    mock.addAfterInsertField(field, value);
    if (!afterInserts.containsKey(mock.type)) afterInserts.put(mock.type, new List<MockObject>());
    if(!afterInserts.get(mock.type).contains(mock)) afterInserts.get(mock.type).add(mock);
  }

  private void mapDependencies(){
    if (needProfiles) loadProfiles();
    if (needUserRoles) loadUserRoles();
    if (needPermissionSets) loadPermissionsets();
    if (needPermissionSetLicenses) loadPermissionsetLicenses();
    if (needUsers) loadUsers();
    for (String name : typeMap.keySet()) typeDependency.put(name,new Set<String>());
    if (typeDependency.containsKey('User')) { // Hierarchical settings might depend on users
      for (String ht : hierarchicalTypeList) typeDependency.get(ht).add('User');
    }

    if (needPermissionSets && needPermissionSetLicenses){ // permission sets might depend on licenses
      typeDependency.get('PermissionSetAssignment').add('PermissionSetLicenseAssign');
    }
    
    for (String refName : pkReferenceMap.keySet()){
      if (!pkMap.containsKey(refName)) throw new TestDataLoaderException('Unknown reference ' + refName);
      MockObject refObj = pkMap.get(refName);
      String parentType = refObj.type;
      for (ReferenceWrapper rw : pkReferenceMap.get(refName)){
        if (rw.deferred) continue; // skip deferred ones.
        String childType = rw.mock.type;
        typeDependency.get(childType).add(parentType);
        if (childType == parentType) rw.mock.addselfReference(rw.field);
      }
    }
    if (log) System.debug('TypeDependency : ' + typeDependency);
    if (log) System.debug('TypeMap : ' + typeMap);
  }

  private void loadProfiles(){
    for (Profile p : [SELECT Id,Name FROM Profile]){
      profileMap.put(p.Name,p.Id);
    }
  }

  private void loadUserRoles(){
    for (UserRole ur : [SELECT Id,Name FROM UserRole]){
      userRoleMap.put(ur.Name,ur.Id);
    }
  }

  private void loadPermissionsets(){
    for (Permissionset p : [SELECT Id, Name FROM Permissionset]){
      permissionsetMap.put(p.Name.toLowerCase(), p.Id);
    }
  }

  private void loadPermissionsetLicenses(){
    for (PermissionsetLicense p : [SELECT Id, DeveloperName FROM PermissionSetLicense]){
      permissionsetLicenseMap.put(p.DeveloperName.toLowerCase(), p.Id);
    }
  }

  private void loadUsers(){
    for (User u : [SELECT Id, Name FROM User WHERE Name in :requestedUsers.keySet()]){
      requestedUsers.put(u.Name, u.Id);
    }
  }

  private void persist(){
    typeCache = new Map<String,Schema.DescribeSobjectResult>();
    for (Schema.DescribeSobjectResult dr : Schema.describeSObjects(new List<String>(typeMap.keySet()))){
      typeCache.put(dr.getName(),dr);
    }
    oldTypeMapSize = typeMap.size();
    globalTypeMap = new Map<String,List<MockObject>>(typeMap);
    persistR();
    updateDeferreds();
    updateAfterInsert();
    finalizeTypeMap();
  }

  private void persistR(){
    for (String typeName : typeDependency.keySet()){
      Set<String> deps = typeDependency.get(typeName);
      if (deps.isEmpty()){
        persistSimple(typeName);
        removeDep(typeName);
      } else if (deps.size() == 1 && deps.contains(typeName)){
        persistParented(typeName);
        removeDep(typeName);
      }
    }
    if (typeMap.size() == oldTypeMapSize) throw new TestDataLoaderException('Can\'t reduce typemap. Circular references? ' + typeDependency);
    oldTypeMapSize = typeMap.size();
    if (!typeMap.isEmpty()) persistR();
  }

  private void updateDeferreds(){
    if (deferreds.isEmpty()) return;
    for (String typeName : deferreds.keySet()){
      List<MockObject> source = deferreds.get(typeName);
      updateList(source, typeName, true, false);
    }
  }

  private void updateAfterInsert(){
    if (afterInserts.isEmpty()) return;
    for (String typeName : afterInserts.keySet()){
      List<MockObject> source = afterInserts.get(typeName);
      updateList(source, typeName, false, true);
    }
  }

  private void finalizeTypeMap(){
    for(List<MockObject> mockList : globalTypeMap.values()){
      for(MockObject mock : mockList){
        mock.isFinalized = true;
      }
    }
  }

  private void removeDep(String s){
    for (Set<String> dep : typeDependency.values()){
      dep.remove(s);
    } 
    typeMap.remove(s);
  }

  private void persistSimple(String typeName){
    List<MockObject> source = typeMap.get(typeName);
    if (source == null) {
      if (log) System.debug('Null for type ' + typeName);
      if (log) System.debug('typeMap: ' + typeMap);
      return;
    }
    persistList(source,typeName);
  }

  private void persistParented(String typeName){
    List<MockObject> source = typeMap.get(typeName);
    integer outstanding = source.size();
    while (outstanding != 0){
      outstanding = 0;
      List<MockObject> parents = new List<MockObject>();
      for (MockObject o : source){
        if (o.getField('Id') == null){
          if (!o.hasSelfReferences()) parents.add(o);
          else {
            outstanding++;
          }
        }
      }
      if (outstanding != 0 && parents.isEmpty()) throw new TestDataLoaderException('Unresolvable parent reference for type ' + typeName + ' with ' + outstanding +' outstanding records : ' + source);
      persistList(parents,typeName);
    }
  }

  private void persistList(List<MockObject> source, String typeName){
    if (source.isEmpty()) return;
    List<sObject> soList = buildObjects(typeName,source, false, false);
    if (log) System.debug('persistList | soList count: ' + soList.size());

    if (soList.isEmpty()) return;

    System.runAs(me) { // HACK: isolate transactions to enable insertion of setup/non setup objects  together
      insert soList;
      /***/
      if (recordMap.containsKey(typeName)) {
        recordMap.get(typeName).addAll(soList);
      } else {
        recordMap.put(typeName, soList);
      }
      if (log) system.debug('typeName: ' + typeName + '; recordMap so far: ' + recordMap);
      /***/
    }

    integer i=0;
    for (integer x = 0; x < source.size();x++){
      MockObject so = source.get(x);
      if (!so.isFinalized){
        Id oid = soList.get(i).Id;
        if (so.createdDate != null) Test.setCreatedDate(oid, so.createdDate);
        so.setField('Id', oid);
        if (so.pk != null) resolveDeps(so);
        i++;
      }
    }
  }

  private void updateList(List<MockObject> source, String typeName, boolean deferred, boolean isAfterInsert){
    if (source.isEmpty()) return;
    List<sObject> soList = buildObjects(typeName, source, deferred, isAfterInsert);
    update (soList);
  }

  private List<sObject> buildObjects(String typeName, List<MockObject> data, boolean deferred, boolean isAfterInsert){
    List<sObject> objects = new List<sObject>();
    for (MockObject mock : data){
      if (mock.isFinalized) continue;
      SObject sob;
      if (templateMap.containsKey(typeName)){
        SObject template = buildObject(typeName, templateMap.get(typeName), deferred, null, false);
        sob = buildObject(typeName, mock, deferred, template, isAfterInsert);
      } else sob = buildObject(typeName, mock, deferred, null, isAfterInsert);
      objects.add(sob);
    }
    return objects;
  }

  private Id resolveRecordType(String typeName, String recordType){
    Id rti = null;
    if (recordTypeMap == null) initRecordTypeMap();
    if (recordTypeMap.containsKey(typeName) && recordTypeMap.get(typeName).containsKey(recordType)){
      rti = recordTypeMap.get(typeName).get(recordType);
    }
    if (rti == null) throw new TestDataLoaderException('Invalid record type ' + recordType + ' for type ' + typeName);
    return rti;
  }

  private sObject buildObject(String typeName, MockObject mock, boolean deferred, SObject template, boolean isAfterInsert){
    if (!typeCache.containsKey(typeName)) throw new TestDataLoaderException('Unknown type ' + typeName);
    SObject sob = template == null ? typeCache.get(typeName).getSObjectType().newSObject() : template;
    if (!deferred && !isAfterInsert) {
      if (mock.recordType != null) {
        sob.put('RecordTypeId', resolveRecordType(typeName, mock.recordType));
      }
      if (mock.profile != null) {
        Id profileId = profileMap.get(mock.profile);
        if (profileId == null) throw new TestDataLoaderException('Invalid profile name ' + mock.profile);
        sob.put('ProfileId', profileId);
      }
      if (mock.userRole != null) {
        Id userRoleId = userRoleMap.get(mock.userRole);
        if (userRoleId == null) throw new TestDataLoaderException('Invalid user role name ' + mock.userRole);
        sob.put('UserRoleId', userRoleId);
      }
      if (mock.hierarchy != null) {
        Id hierarchyId = profileMap.get(mock.hierarchy);
        if (hierarchyId == null) hierarchyId = getIdForPk(mock.hierarchy);
        if (hierarchyId == null) throw new TestDataLoaderException('Invalid profile or user ' + mock.hierarchy + ' specified for hierarchical setting');
        sob.put('SetupOwnerId', hierarchyId);
      }
      if (mock.permissionset != null){
        Id permissionsetId = permissionsetMap.get(mock.permissionset.toLowerCase());
        if (permissionsetId == null) throw new TestDataLoaderException('Invalid permission set name ' + mock.permissionset);
        sob.put('PermissionSetId', permissionsetId);
      }
      if (mock.permissionsetLicense != null){
        Id permissionsetLicenseId = permissionsetLicenseMap.get(mock.permissionsetLicense.toLowerCase());
        if (permissionsetLicenseId == null) throw new TestDataLoaderException('Invalid permission set license name ' + mock.permissionsetLicense);
        sob.put('PermissionSetLicenseId', permissionsetLicenseId);
      }
    }else{
      sob.put('Id', mock.getField('Id'));
    }
    for (String field : mock.fieldNames){
      Schema.SObjectField sField = typeCache.get(typeName).fields.getMap().get(field);
      if (sField == null) throw new TestDataLoaderException('Invalid field ' + field + ' for type ' + typeName);
      if (!deferred){ // no deferred userrefs. 
        String userRef = mock.getUserRef(field);
        if (userRef != null) {
          if (!requestedUsers.containsKey(userRef)) throw new TestDataLoaderException('Invalid user reference ' + userRef + ' for field ' + field + ' for type ' + typeName);
          mock.setField(field, requestedUsers.get(userRef));
        }
      }
      if (deferred != mock.isDeferred(field)) continue;
      Schema.DisplayType dtype = sField.getDescribe().getType();
      sob.put(field,mock.getFieldAs(field,dtype,isAfterInsert));
    }
    return sob;
  }


  private void resolveDeps(MockObject so){
    String pkName = so.pk;
    String refid = so.getField('Id');
    if (log) System.debug('pkName:' + pkName + ' pkReferenceMap:' + pkReferenceMap);
    List<ReferenceWrapper> refList = pkReferenceMap.get(pkName);
    if (refList == null) return;
    for (ReferenceWrapper rw : refList){
      rw.mock.setField(rw.field,refid);
    }
  }

  class ReferenceWrapper{
    MockObject mock {get;set;}
    String field {get;set;}
    boolean deferred {get;set;}
    ReferenceWrapper(MockObject mock,String field, boolean deferred){
      this.mock = mock;
      this.field = field;
      this.deferred = deferred;
    }
  }
  class MockObject {
    private Map<String,String> fields = new Map<String,String>();
    private Map<String,String> afterInsertFields = new Map<String,String>();
    private Set<String> selfRefs = new Set<String>();
    private Set<String> deferredRefs = new Set<String>();
    private Set<String> userRefs = new Set<String>();
    DateTime createdDate;
    String type {get;set;}
    String pk {get;set;}
    String recordType {get;set;}
    String profile {get;set;}
    String userRole {get;set;}
    String hierarchy {get;set;}
    String permissionset {get;set;}
    String permissionsetLicense {get;set;}
    boolean isFinalized {get;set;}
    Set<String> fieldNames {get{return fields.keySet();}}

    public boolean hasDeferred {get {return !deferredRefs.isEmpty();}}
    public boolean hasUserRefs {get {return !userRefs.isEmpty();}}
    public boolean hasAfterInsertFields {get {return !afterInsertFields.isEmpty();}}

    boolean isDeferred(String name){
      return deferredRefs.contains(name);
    }

    void addUserRef(String field, String name){
      userRefs.add(field);
      fields.put(field, name);
    }

    String getUserRef(String field){
      if (userRefs.contains(field)) return fields.get(field);
      return null;
    }

    void addDeferredReference(String field){
      deferredRefs.add(field);
    }

    void addSelfReference(String field){
      selfRefs.add(field);
    }

    boolean hasSelfReferences(){
      return !selfRefs.isEmpty();
    }

    void setField(String field,String value){
      if ('createddate'.equals(field.toLowerCase())) {
        this.createdDate = TestDataLoader.parseDateTime(value);
      } else fields.put(field,value);
      selfRefs.remove(field);
    }

    String getField(String field){
      return fields.get(field);
    }

    void addAfterInsertField(String field, String value){
      afterInsertFields.put(field,value);
    }

    object getFieldAs(String field,Schema.DisplayType dtype, boolean isAfterInsert){
      String value = fields.get(field);
      if (isAfterInsert && afterInsertFields.containsKey(field)){
        value = afterInsertFields.get(field);
      }
      if (value == null) return null; // null is null
      if (dtype == Schema.DisplayType.Email ||
          dtype == Schema.DisplayType.Id ||
          dtype == Schema.DisplayType.Picklist ||
          dtype == Schema.DisplayType.MULTIPICKLIST ||
          dtype == Schema.DisplayType.String ||
          dtype == Schema.DisplayType.URL ||
          dtype == Schema.DisplayType.PHONE ||
          dtype == Schema.DisplayType.TEXTAREA ||
          dtype == Schema.DisplayType.Reference ||
          dtype == Schema.DisplayType.Combobox){
        return value;
      }else if (dtype == Schema.DisplayType.Boolean){
        return Boolean.valueOf(value);
      }else if (dtype == Schema.DisplayType.Date){
        return TestDataLoader.parseDate(value);
      }else if (dtype == Schema.DisplayType.DateTime){
        return TestDataLoader.parseDateTime(value);
      }else if (dtype == Schema.DisplayType.Double){
        return Double.valueOf(value);
      }else if (dtype == Schema.DisplayType.Currency){
        return Double.valueOf(value);
      }else if (dtype == Schema.DisplayType.Percent){
        return Double.valueOf(value);
      }else if (dtype == Schema.DisplayType.base64){
        return Blob.valueOf(value);
      }else if (dtype == Schema.DisplayType.Integer){
        return Integer.valueOf(value);
      }else throw new TestDataLoaderException('Unhandled type ' + dtype + ' for field ' + field + ' in type ' + type);
    }
  }

  // nothing fancy, just "today[+|-][day(s)|month(s)|year(s)]" 
  public static Date parseDate(String expression){
    Matcher m = expressionPattern.matcher(expression.trim().toLowerCase());
    if (!m.matches()) return Date.valueOf(expression);
    String sign = m.group(1);
    Integer value = Integer.valueOf(m.group(2));
    if (sign == '-') value = -value;
    String unit = m.group(3);
    if (unit.endsWith('s')) unit = unit.substring(0, unit.length() - 1);
    if (unit == 'day') return Date.today().addDays(value);
    if (unit == 'month') return Date.today().addMonths(value);
    if (unit == 'year') return Date.today().addYears(value);
    throw new TestDataLoaderException('Unknown unit: ' + unit + ' in date expression' + expression);
  }

  private static DateTime parseDateTimeWithJSONFallback(String value){
    try {
      return DateTime.valueOf(value);
    } catch (TypeException e) {
      String dummyJSON = '{"a" : "' + value + '"}';  
      JSONParser parser = JSON.createParser(dummyJSON);
      parser.nextToken();
      parser.nextValue();
      return parser.getDateTimeValue();
    }
  }

  public static DateTime parseDateTime(String expression){
    Matcher m = expressionPattern.matcher(expression.trim().toLowerCase());
    if (!m.matches()) return parseDateTimeWithJSONFallback(expression);
    String sign = m.group(1);
    Integer value = Integer.valueOf(m.group(2));
    if (sign == '-') value = -value;
    String unit = m.group(3);
    if (unit.endsWith('s')) unit = unit.substring(0, unit.length() - 1);
    if (unit == 'day') return DateTime.now().addDays(value);
    if (unit == 'month') return DateTime.now().addMonths(value);
    if (unit == 'year') return DateTime.now().addYears(value);
    if (unit == 'hour') return DateTime.now().addHours(value);
    if (unit == 'minute') return DateTime.now().addMinutes(value);
    if (unit == 'second') return DateTime.now().addSeconds(value);
    throw new TestDataLoaderException('Unknown unit: ' + unit + ' in date expression' + expression);
  }
}