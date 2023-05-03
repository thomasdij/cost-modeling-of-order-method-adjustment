-- This file sets up the tables for existing costs, these tables are often used in other queries so
-- they were set up as permenant 
CREATE TABLE billing_report (date_and_ship_to_address VARCHAR(42), article_id VARCHAR(7), pick_type VARCHAR(3), each_per_pallet INTEGER, each_per_case INTEGER, quantity_eaches_requested_for_order INTEGER, pallet_picks INTEGER, case_picks INTEGER, each_picks INTEGER);

CREATE TABLE cost_by_pick (product_type VARCHAR(3), pick_uom VARCHAR(8), cost_per_pick NUMERIC(10,3));

CREATE TABLE pick_type_product_type (pick_type VARCHAR(3), product_type VARCHAR(3));

COPY pick_type_product_type (pick_type, product_type)
FROM 'path1'
DELIMITER ','
CSV HEADER;
SELECT * FROM billing_report JOIN pick_type_product_type ON billing_report.pick_type = pick_type_product_type.pick_type;

COPY cost_by_pick(product_type, pick_uom, cost_per_pick)
FROM 'path2'
DELIMITER ','
CSV HEADER;

COPY billing_report (date_and_ship_to_address ,  article_id ,  pick_type ,  each_per_pallet ,  each_per_case ,  quantity_eaches_requested_for_order ,  pallet_picks ,  case_picks ,  each_picks)
FROM 'path3'
DELIMITER '	'
CSV HEADER;

-- Additional columns detailing costs are useful to permenantly keep on hand for future queries
-- Because of this, permenant updates are made instead of CTEs or temp tables

ALTER TABLE billing_report ADD COLUMN cost_of_pallet_picks NUMERIC(10,3), ADD COLUMN cost_of_case_picks NUMERIC(10,3), ADD COLUMN cost_of_each_picks NUMERIC(10,3), ADD COLUMN line_pick_cost NUMERIC(10,3);

ALTER TABLE billing_report ADD COLUMN product_type VARCHAR(3);

-- The product type is added so that pick costs can later be calculated, pick costs are different for
-- each product type
UPDATE billing_report
SET product_type = pick_type_product_type.product_type
FROM pick_type_product_type
WHERE billing_report.pick_type = pick_type_product_type.pick_type;

CREATE TABLE existing_pick_costs AS SELECT * FROM billing_report;

-- Cost of pallet picks is found as the number of pallet picks for a given line times the cost of
-- picking that particular type of pallet for the product type of that line given in the cost_by_pick
-- table
UPDATE existing_pick_costs
SET cost_of_pallet_picks = pallet_picks * (
    SELECT cost_per_pick
    FROM cost_by_pick
    WHERE cost_by_pick.product_type = existing_pick_costs.product_type
    AND cost_by_pick.pick_uom = 'Pallet'
);

-- Cost of case picks is found as the number of case picks for a given line times the cost of
-- picking that particular type of case for the product type of that line given in the cost_by_pick
-- table
UPDATE existing_pick_costs
SET cost_of_case_picks = case_picks * (
    SELECT cost_per_pick
    FROM cost_by_pick
    WHERE cost_by_pick.product_type = existing_pick_costs.product_type
    AND cost_by_pick.pick_uom = 'Case'
);

-- Cost of each picks is found as the number of each picks for a given line times the cost of
-- picking that particular type of each for the product type of that line given in the cost_by_pick
-- table
UPDATE existing_pick_costs
SET cost_of_each_picks = each_picks * (
    SELECT cost_per_pick
    FROM cost_by_pick
    WHERE cost_by_pick.product_type = existing_pick_costs.product_type
    AND cost_by_pick.pick_uom = 'Each'
);

-- Total cost of all picks (each, case, pallet) for a given line are calculated
UPDATE existing_pick_costs
SET line_pick_cost = cost_of_pallet_picks + cost_of_case_picks + cost_of_each_picks;

-- date_and_ship_to_address, article_id is a frequent identifier in queries so an index is created for it
CREATE INDEX idx_existing_pick_costs_date_and_ship_to_address_article_id
ON existing_pick_costs(date_and_ship_to_address, article_id);
