-- trigger to automatically extract pre-defined ngsi-ld members and store them in regular fields (for query performance)
CREATE OR REPLACE FUNCTION csource_extract_jsonb_fields() RETURNS trigger AS $_$
DECLARE
    l_rec RECORD;
    l_entityinfo_count INTEGER;
    l_attributeinfo_count INTEGER;
BEGIN
    IF (TG_OP = 'INSERT' AND NEW.data IS NOT NULL) OR 
        (TG_OP = 'UPDATE' AND OLD.data IS NULL AND NEW.data IS NOT NULL) OR 
        (TG_OP = 'UPDATE' AND OLD.data IS NOT NULL AND NEW.data IS NULL) OR 
        (TG_OP = 'UPDATE' AND OLD.data IS NOT NULL AND NEW.data IS NOT NULL AND OLD.data <> NEW.data) THEN 
      NEW.type = NEW.data#>>'{@type,0}';
      NEW.tenant_id = NEW.data#>>'{https://uri.etsi.org/ngsi-ld/default-context/tenant,0,@value}';
      NEW.name = NEW.data#>>'{https://uri.etsi.org/ngsi-ld/name,0,@value}';
      NEW.description = NEW.data#>>'{https://uri.etsi.org/ngsi-ld/description,0,@value}';
      NEW.timestamp_start = (NEW.data#>>'{https://uri.etsi.org/ngsi-ld/timestamp,0,https://uri.etsi.org/ngsi-ld/start,0,@value}')::TIMESTAMP;
      NEW.timestamp_end = (NEW.data#>>'{https://uri.etsi.org/ngsi-ld/timestamp,0,https://uri.etsi.org/ngsi-ld/end,0,@value}')::TIMESTAMP;
      NEW.location = ST_SetSRID(ST_GeomFromGeoJSON( NEW.data#>>'{https://uri.etsi.org/ngsi-ld/location,0,@value}' ), 4326);
      NEW.expires = (NEW.data#>>'{https://uri.etsi.org/ngsi-ld/expires,0,@value}')::TIMESTAMP;
      NEW.endpoint = NEW.data#>>'{https://uri.etsi.org/ngsi-ld/endpoint,0,@value}';
      NEW.internal = COALESCE((NEW.data#>>'{https://uri.etsi.org/ngsi-ld/internal,0,@value}')::BOOLEAN, FALSE);

      NEW.has_registrationinfo_with_attrs_only = false;
      NEW.has_registrationinfo_with_entityinfo_only = false;

      FOR l_rec IN SELECT value FROM jsonb_array_elements(NEW.data#>'{https://uri.etsi.org/ngsi-ld/information}')
      LOOP        
          SELECT INTO l_entityinfo_count count(*) FROM jsonb_array_elements( l_rec.value#>'{https://uri.etsi.org/ngsi-ld/entities}' );
          SELECT INTO l_attributeinfo_count count(*) FROM jsonb_array_elements( l_rec.value#>'{https://uri.etsi.org/ngsi-ld/propertyNames}' );
          SELECT INTO l_attributeinfo_count count(*)+l_attributeinfo_count FROM jsonb_array_elements( l_rec.value#>'{https://uri.etsi.org/ngsi-ld/relationshipNames}' );

          IF (NEW.has_registrationinfo_with_attrs_only = false) THEN
              NEW.has_registrationinfo_with_attrs_only = (l_entityinfo_count = 0 AND l_attributeinfo_count > 0);
          END IF;

          IF (NEW.has_registrationinfo_with_entityinfo_only = false) THEN
              NEW.has_registrationinfo_with_entityinfo_only = (l_entityinfo_count > 0 AND l_attributeinfo_count = 0);
          END IF;
      END LOOP;
    END IF;

    RETURN NEW;
END;
$_$ LANGUAGE plpgsql;



-- trigger to automatically extract pre-defined ngsi-ld members and store them in information table
CREATE OR REPLACE FUNCTION csource_extract_jsonb_fields_to_information_table() RETURNS trigger AS $_$
DECLARE
    l_rec RECORD;
    l_group_id csourceinformation.group_id%TYPE;
BEGIN    

    IF (TG_OP = 'INSERT' AND NEW.data IS NOT NULL) OR 
        (TG_OP = 'UPDATE' AND OLD.data IS NULL AND NEW.data IS NOT NULL) OR 
        (TG_OP = 'UPDATE' AND OLD.data IS NOT NULL AND NEW.data IS NULL) OR 
        (TG_OP = 'UPDATE' AND OLD.data IS NOT NULL AND NEW.data IS NOT NULL AND OLD.data <> NEW.data) THEN 

      IF TG_OP = 'UPDATE' THEN
          DELETE FROM csourceinformation where csource_id = NEW.id;
      END IF;
      
      FOR l_rec IN SELECT value FROM jsonb_array_elements(NEW.data#>'{https://uri.etsi.org/ngsi-ld/information}')
      LOOP        
          -- RAISE NOTICE '%', rec.value;
          SELECT nextval('csourceinformation_group_id_seq') INTO l_group_id;

          -- id takes precedence over idPattern. so, only store idPattern if id is empty. this makes queries much easier/faster.
          INSERT INTO csourceinformation (csource_id, group_id, entity_id, entity_type, entity_idpattern) 
              SELECT NEW.id, 
                    l_group_id,
                    value#>>'{@id}', 
                    value#>>'{@type,0}', 
                    CASE WHEN value#>>'{@id}' IS NULL THEN value#>>'{https://uri.etsi.org/ngsi-ld/idPattern,0,@value}' END
                  FROM jsonb_array_elements( l_rec.value#>'{https://uri.etsi.org/ngsi-ld/entities}');

          INSERT INTO csourceinformation (csource_id, group_id, property_id) 
              SELECT NEW.id, 
                    l_group_id,
                    value#>>'{@id}' 
                  FROM jsonb_array_elements( l_rec.value#>'{https://uri.etsi.org/ngsi-ld/propertyNames}');
          
          INSERT INTO csourceinformation (csource_id, group_id, relationship_id) 
              SELECT NEW.id, 
                    l_group_id,
                    value#>>'{@id}'
              FROM jsonb_array_elements( l_rec.value#>'{https://uri.etsi.org/ngsi-ld/relationshipNames}');
          
      END LOOP;

    END IF;

    RETURN NEW;
END;
$_$ LANGUAGE plpgsql;