CREATE TABLE billing_report (date_and_ship_to_address VARCHAR(42), article_id VARCHAR(7), pick_type VARCHAR(3), each_per_pallet INTEGER, each_per_case INTEGER, quantity_eaches_requested_for_order INTEGER, pallet_picks INTEGER, case_picks INTEGER, each_picks INTEGER);

CREATE TABLE cost_by_pick (product_type VARCHAR(3), pick_uom VARCHAR(8), cost_per_pick NUMERIC(10,3));

CREATE TABLE pick_type_product_type (pick_type VARCHAR(3), product_type VARCHAR(3));

COPY pick_type_product_type (pick_type, product_type)
FROM 'C:\Users\tddij\Desktop\Databases\Order_By_Customer\Pick_Type_Key_for_SQL.csv'
DELIMITER ','
CSV HEADER;
SELECT * FROM billing_report JOIN pick_type_product_type ON billing_report.pick_type = pick_type_product_type.pick_type;

COPY cost_by_pick(product_type, pick_uom, cost_per_pick)
FROM 'C:\Users\tddij\Desktop\Databases\Order_By_Customer\Cost_by_Pick_for_SQL.csv'
DELIMITER ','
CSV HEADER;

COPY billing_report (date_and_ship_to_address ,  article_id ,  pick_type ,  each_per_pallet ,  each_per_case ,  quantity_eaches_requested_for_order ,  pallet_picks ,  case_picks ,  each_picks)
FROM 'C:\Users\tddij\Desktop\Databases\Order_By_Customer\Tab_delim_SPWR_BILLING_Report_for_SQL.txt'
DELIMITER '	'
CSV HEADER;

ALTER TABLE billing_report ADD COLUMN cost_of_pallet_picks NUMERIC(10,3), ADD COLUMN cost_of_case_picks NUMERIC(10,3), ADD COLUMN cost_of_each_picks NUMERIC(10,3), ADD COLUMN line_pick_cost NUMERIC(10,3);

ALTER TABLE billing_report ADD COLUMN product_type VARCHAR(3);

UPDATE billing_report
SET product_type = pick_type_product_type.product_type
FROM pick_type_product_type
WHERE billing_report.pick_type = pick_type_product_type.pick_type;

CREATE TABLE existing_pick_costs AS SELECT * FROM billing_report;

UPDATE existing_pick_costs
SET cost_of_pallet_picks = pallet_picks * (
    SELECT cost_per_pick
    FROM cost_by_pick
    WHERE cost_by_pick.product_type = existing_pick_costs.product_type
    AND cost_by_pick.pick_uom = 'Pallet'
);

UPDATE existing_pick_costs
SET cost_of_case_picks = case_picks * (
    SELECT cost_per_pick
    FROM cost_by_pick
    WHERE cost_by_pick.product_type = existing_pick_costs.product_type
    AND cost_by_pick.pick_uom = 'Case'
);

UPDATE existing_pick_costs
SET cost_of_each_picks = each_picks * (
    SELECT cost_per_pick
    FROM cost_by_pick
    WHERE cost_by_pick.product_type = existing_pick_costs.product_type
    AND cost_by_pick.pick_uom = 'Each'
);

UPDATE existing_pick_costs
SET line_pick_cost = cost_of_pallet_picks + cost_of_case_picks + cost_of_each_picks;

SELECT SUM(line_pick_cost) FROM existing_pick_costs;



