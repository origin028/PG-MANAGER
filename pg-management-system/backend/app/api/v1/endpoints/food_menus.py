import uuid
from typing import List, Optional
from fastapi import APIRouter, Depends, Query, status
import sqlalchemy as sa
from sqlalchemy.orm import Session

from app.core.exceptions import BadRequestError, ConflictError, NotFoundError
from app.dependencies import get_current_user, get_db, require_roles, verify_property_access
from app.models.food_menu import FoodMenu
from app.models.property import Property
from app.models.user import User
from app.schemas.common import APIResponse
from app.schemas.food_menu import FoodMenuCreate, FoodMenuRead, FoodMenuUpdate
from app.services.audit_service import record_audit_log

router = APIRouter()


@router.post("", response_model=APIResponse[FoodMenuRead], status_code=status.HTTP_201_CREATED)
def create_food_menu_item(
    payload: FoodMenuCreate,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Creates a weekly food menu item for a property."""
    verify_property_access(payload.property_id, current_user, db)

    property_record = db.get(Property, payload.property_id)
    if not property_record:
        raise NotFoundError("Property not found.")

    day = payload.day_of_week.strip().upper()
    meal = payload.meal_type.strip().upper()

    existing = db.scalar(
        sa.select(FoodMenu).where(
            FoodMenu.property_id == payload.property_id,
            FoodMenu.day_of_week == day,
            FoodMenu.meal_type == meal,
        )
    )
    if existing:
        raise ConflictError(f"A food menu entry for {day} {meal} already exists for this property.")

    menu_item = FoodMenu(
        property_id=payload.property_id,
        day_of_week=day,
        meal_type=meal,
        start_time=payload.start_time,
        end_time=payload.end_time,
        dishes=payload.dishes,
        is_active=payload.is_active,
    )
    db.add(menu_item)
    db.commit()
    db.refresh(menu_item)

    record_audit_log(
        db=db,
        action="CREATE_FOOD_MENU",
        resource_type="food_menus",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name if current_user.role else None,
        property_id=menu_item.property_id,
        resource_id=str(menu_item.id),
        details={"day_of_week": day, "meal_type": meal},
    )

    read_data = FoodMenuRead(
        id=menu_item.id,
        property_id=menu_item.property_id,
        day_of_week=menu_item.day_of_week,
        meal_type=menu_item.meal_type,
        start_time=menu_item.start_time,
        end_time=menu_item.end_time,
        dishes=menu_item.dishes or [],
        is_active=menu_item.is_active,
        created_at=menu_item.created_at,
        updated_at=menu_item.updated_at,
        property_name=property_record.name,
    )
    return APIResponse(
        success=True,
        message=f"Food menu item for {day} {meal} created successfully.",
        data=read_data,
    )


@router.get("", response_model=APIResponse[List[FoodMenuRead]], status_code=status.HTTP_200_OK)
def list_food_menu(
    property_id: uuid.UUID = Query(..., description="Property ID filter"),
    day_of_week: Optional[str] = Query(None, description="Optional day filter"),
    meal_type: Optional[str] = Query(None, description="Optional meal type filter"),
    is_active: Optional[bool] = Query(None, description="Optional active status filter"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Lists weekly food menu items for a property."""
    if current_user.role.name != "RESIDENT":
        verify_property_access(property_id, current_user, db)

    query = sa.select(FoodMenu).where(FoodMenu.property_id == property_id)

    if day_of_week:
        query = query.where(FoodMenu.day_of_week == day_of_week.strip().upper())
    if meal_type:
        query = query.where(FoodMenu.meal_type == meal_type.strip().upper())
    if is_active is not None:
        query = query.where(FoodMenu.is_active == is_active)

    query = query.order_by(FoodMenu.day_of_week.asc(), FoodMenu.meal_type.asc())
    items = db.scalars(query).all()

    property_record = db.get(Property, property_id)
    prop_name = property_record.name if property_record else None

    data = [
        FoodMenuRead(
            id=item.id,
            property_id=item.property_id,
            day_of_week=item.day_of_week,
            meal_type=item.meal_type,
            start_time=item.start_time,
            end_time=item.end_time,
            dishes=item.dishes or [],
            is_active=item.is_active,
            created_at=item.created_at,
            updated_at=item.updated_at,
            property_name=prop_name,
        )
        for item in items
    ]
    return APIResponse(
        success=True,
        message=f"Retrieved {len(data)} food menu items.",
        data=data,
    )


@router.get("/{menu_id}", response_model=APIResponse[FoodMenuRead], status_code=status.HTTP_200_OK)
def get_food_menu_item(
    menu_id: uuid.UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Retrieves single food menu entry."""
    item = db.get(FoodMenu, menu_id)
    if not item:
        raise NotFoundError("Food menu item not found.")

    if current_user.role.name != "RESIDENT":
        verify_property_access(item.property_id, current_user, db)

    read_data = FoodMenuRead(
        id=item.id,
        property_id=item.property_id,
        day_of_week=item.day_of_week,
        meal_type=item.meal_type,
        start_time=item.start_time,
        end_time=item.end_time,
        dishes=item.dishes or [],
        is_active=item.is_active,
        created_at=item.created_at,
        updated_at=item.updated_at,
        property_name=item.property.name if item.property else None,
    )
    return APIResponse(
        success=True,
        message="Food menu item retrieved successfully.",
        data=read_data,
    )


@router.get(
    "/property/{property_id}/weekly",
    response_model=APIResponse[List[FoodMenuRead]],
    status_code=status.HTTP_200_OK,
    summary="Get Weekly Food Menu by Property Path (Alias)",
    include_in_schema=False,
)
def get_weekly_food_menu_by_property_alias(
    property_id: uuid.UUID,
    day_of_week: Optional[str] = Query(None),
    meal_type: Optional[str] = Query(None),
    is_active: Optional[bool] = Query(None),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Path-based alias for list_food_menu."""
    return list_food_menu(
        property_id=property_id,
        day_of_week=day_of_week,
        meal_type=meal_type,
        is_active=is_active,
        current_user=current_user,
        db=db,
    )


@router.patch("/{menu_id}", response_model=APIResponse[FoodMenuRead], status_code=status.HTTP_200_OK)
def update_food_menu_item(
    menu_id: uuid.UUID,
    payload: FoodMenuUpdate,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Updates a food menu entry."""
    item = db.get(FoodMenu, menu_id)
    if not item:
        raise NotFoundError("Food menu item not found.")

    verify_property_access(item.property_id, current_user, db)

    update_data = payload.model_dump(exclude_unset=True)
    if not update_data:
        read_data = FoodMenuRead(
            id=item.id,
            property_id=item.property_id,
            day_of_week=item.day_of_week,
            meal_type=item.meal_type,
            start_time=item.start_time,
            end_time=item.end_time,
            dishes=item.dishes or [],
            is_active=item.is_active,
            created_at=item.created_at,
            updated_at=item.updated_at,
            property_name=item.property.name if item.property else None,
        )
        return APIResponse(success=True, message="No changes requested.", data=read_data)

    if "day_of_week" in update_data and update_data["day_of_week"]:
        item.day_of_week = update_data["day_of_week"].strip().upper()
    if "meal_type" in update_data and update_data["meal_type"]:
        item.meal_type = update_data["meal_type"].strip().upper()
    if "start_time" in update_data:
        item.start_time = update_data["start_time"]
    if "end_time" in update_data:
        item.end_time = update_data["end_time"]
    if "dishes" in update_data and update_data["dishes"] is not None:
        item.dishes = update_data["dishes"]
    if "is_active" in update_data and update_data["is_active"] is not None:
        item.is_active = update_data["is_active"]

    record_audit_log(
        db=db,
        action="UPDATE_FOOD_MENU",
        resource_type="food_menus",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name if current_user.role else None,
        property_id=item.property_id,
        resource_id=str(item.id),
        details={"updated_fields": list(update_data.keys())},
    )

    db.commit()
    db.refresh(item)

    read_data = FoodMenuRead(
        id=item.id,
        property_id=item.property_id,
        day_of_week=item.day_of_week,
        meal_type=item.meal_type,
        start_time=item.start_time,
        end_time=item.end_time,
        dishes=item.dishes or [],
        is_active=item.is_active,
        created_at=item.created_at,
        updated_at=item.updated_at,
        property_name=item.property.name if item.property else None,
    )
    return APIResponse(
        success=True,
        message="Food menu item updated successfully.",
        data=read_data,
    )


@router.delete("/{menu_id}", status_code=status.HTTP_200_OK)
def delete_food_menu_item(
    menu_id: uuid.UUID,
    current_user: User = Depends(require_roles("SUPER_ADMIN", "ADMIN", "OWNER", "PROPERTY_MANAGER")),
    db: Session = Depends(get_db),
):
    """Deletes a food menu entry."""
    item = db.get(FoodMenu, menu_id)
    if not item:
        raise NotFoundError("Food menu item not found.")

    verify_property_access(item.property_id, current_user, db)

    record_audit_log(
        db=db,
        action="DELETE_FOOD_MENU",
        resource_type="food_menus",
        user_id=current_user.id,
        user_email=current_user.email,
        user_role=current_user.role.name if current_user.role else None,
        property_id=item.property_id,
        resource_id=str(item.id),
        details={"day_of_week": item.day_of_week, "meal_type": item.meal_type},
    )

    db.delete(item)
    db.commit()

    return APIResponse(
        success=True,
        message="Food menu item deleted successfully.",
        data={"deleted_id": str(menu_id)},
    )
